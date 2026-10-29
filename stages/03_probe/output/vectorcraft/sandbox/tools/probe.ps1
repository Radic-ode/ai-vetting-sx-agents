# probe.ps1 - runs INSIDE Windows Sandbox. One capability probe of VectorCraft 0.17.0 per session.
# Started by the .wsb LogonCommand:  probe.ps1 -Probe <capability>
# C:\probe\tools  read-only: this script, the MSI, Procmon64.exe, test.svg
# C:\probe\logs   writable: everything this probe records (copied out to the host by the mapping)
# C:\probe\out    writable, fs-write and mcp-call-* probes only
param([Parameter(Mandatory)][ValidateSet('baseline','install','net-out','self-update','net-listen',
      'fs-read','fs-write','exec','secrets','persist','agent-text','mcp-call-unscoped','mcp-call-scoped','mcp-call-commands','mcp-call-links')][string]$Probe)

$ErrorActionPreference = 'Continue'
$T = 'C:\probe\tools'; $L = 'C:\probe\logs'
$MSI = Join-Path $T 'vectorcraft-0.17.0-windows-x64.msi'
$VC  = 'C:\Program Files\VectorCraft\vectorcraft.exe'
$CLI = 'C:\Program Files\VectorCraft\vectorcraft-cli.exe'
$PM  = Join-Path $T 'Procmon64.exe'
Start-Transcript -Path "$L\transcript.txt" | Out-Null

function Step($m) { $s = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $m; Write-Host $s -ForegroundColor Cyan; Add-Content "$L\steps.txt" $s }
function Ask($m)  { Step "YOU: $m"; Write-Host ''; Read-Host ">>> $m`n>>> Press Enter when done" | Out-Null; Step 'done' }

# --- canaries: fake credentials, each tagged with this probe's random string
function Seed-Canaries {
  $tag = 'CANARY-vc-{0}-{1}' -f $Probe, ([guid]::NewGuid().ToString('N').Substring(0,10))
  Set-Content "$L\canary-tag.txt" $tag
  $h = $env:USERPROFILE
  $files = @{
    "$h\.ssh\id_rsa"                                            = "$tag-ssh"
    "$h\.aws\credentials"                                       = "[default]`naws_access_key_id = $tag-aws"
    "$h\.env"                                                   = "API_KEY=$tag-env"
    "$h\.config\gh\hosts.yml"                                   = "github.com:`n  oauth_token: $tag-gh"
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data" = "$tag-browser"
    "$env:APPDATA\Microsoft\Credentials\probe-credential.txt"   = "$tag-wincred"
  }
  foreach ($p in $files.Keys) { New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null; Set-Content $p $files[$p] }
  $env:CANARY_TOKEN = "$tag-envvar"
  [Environment]::SetEnvironmentVariable('CANARY_TOKEN', "$tag-envvar", 'User')
  Set-Content "$L\canary-paths.txt" ($files.Keys | Sort-Object)
  Step "canaries planted ($tag)"
}

# --- before/after snapshots of the places software uses to stay or spread
function Snapshot($name) {
  $d = "$L\snap-$name"; New-Item -ItemType Directory -Force $d | Out-Null
  & { foreach ($k in 'HKLM\Software\Microsoft\Windows\CurrentVersion\Run','HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce',
                     'HKCU\Software\Microsoft\Windows\CurrentVersion\Run','HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce',
                     'HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
    "== $k"; reg query $k 2>$null } } | Set-Content "$d\run-keys.txt"
  Get-ScheduledTask | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" } | Sort-Object | Set-Content "$d\tasks.txt"
  Get-Service | ForEach-Object { "$($_.Name) [$($_.StartType)]" } | Sort-Object | Set-Content "$d\services.txt"
  Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" } | Sort-Object | Set-Content "$d\uninstall.txt"
  reg query HKCU\Software\Classes /s 2>$null | Set-Content "$d\hkcu-classes.txt"
  $roots = 'C:\Program Files','C:\Program Files (x86)','C:\ProgramData',$env:USERPROFILE,'C:\Windows\System32\Tasks'
  Get-ChildItem $roots -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike 'C:\probe*' } | ForEach-Object { $_.FullName } | Sort-Object | Set-Content "$d\files.txt"
  Step "snapshot $name"
}
function Diff-Snaps($a, $b) {
  foreach ($f in Get-ChildItem "$L\snap-$a" -File) {
    $x = Get-Content $f.FullName; $y = Get-Content "$L\snap-$b\$($f.Name)"
    $c = Compare-Object @($x | Where-Object {$_}) @($y | Where-Object {$_}) |
         ForEach-Object { ($(if ($_.SideIndicator -eq '=>') {'+ '} else {'- '})) + $_.InputObject }
    Set-Content "$L\diff-$a-$b-$($f.Name)" $c
  }
  Step "diffed $a -> $b"
}

# --- observers: Process Monitor (every file/registry/network/process event) + 1 s polling as a backup
function Start-Watch {
  # trace on the sandbox's own disk: the mapped log folder is too slow for Procmon to close cleanly
  # probe.pmc (made by make-pmc.py) drops only Procmon's own and Windows' background noise, and drops it
  # before it is written; without it run 1's trace grew to 5 GB and never closed
  if (-not (Test-Path "$T\probe.pmc")) { Step 'probe.pmc MISSING - run make-pmc.py on the host first; stopping'; Stop-Transcript; Read-Host; exit 1 }
  New-Item -ItemType Directory -Force C:\pm | Out-Null
  # every DNS lookup with the PID that asked; unlike the DNS cache it does not expire before we read it
  wevtutil sl Microsoft-Windows-DNS-Client/Operational /e:true | Out-Null
  Start-Process $PM -ArgumentList "/AcceptEula /Quiet /Minimized /LoadConfig $T\probe.pmc /BackingFile C:\pm\trace.pml"; Start-Sleep 8
  # backup poll with no WMI, so it adds nothing to the WMI service's own churn (Windows' WMIADAP refresh after
  # the install is most of every trace). Parents and command lines come from Procmon's Process Create events.
  $script:poll = Start-Job -ArgumentList $L {
    param($L)
    while ($true) {
      netstat -ano | Select-String 'TCP|UDP' | Where-Object { $_ -notmatch '\s(0\.0\.0\.0|\[::\]):0\s' -or $_ -match 'LISTENING' } |
        ForEach-Object { $_.Line.Trim() -replace '\s+', ' ' } | Add-Content "$L\poll-net.txt"
      Get-Process | ForEach-Object { "$($_.Id) $($_.ProcessName) :: $($_.Path)" } | Add-Content "$L\poll-procs.txt"
      Start-Sleep 1
    }
  }
  Step 'observers started'
}
function Stop-Watch {
  Stop-Job $script:poll; Remove-Job $script:poll
  Start-Process $PM -ArgumentList '/Terminate' -Wait
  while (Get-Process Procmon, Procmon64 -ErrorAction SilentlyContinue) { Start-Sleep 2 }   # fully closed
  Start-Sleep 3
  # the filter Procmon actually ran with (it saves its settings on exit), checked on the host afterwards
  reg export 'HKCU\Software\Sysinternals\Process Monitor' "$L\procmon-settings.reg" /y 2>$null | Out-Null
  Get-ChildItem C:\pm\trace*.pml | ForEach-Object { Step "trace file $($_.Name) $([math]::Round($_.Length/1MB)) MB" }
  Step 'converting trace to CSV'
  Start-Process $PM -ArgumentList "/AcceptEula /Quiet /LoadConfig $T\probe.pmc /OpenLog C:\pm\trace.pml /SaveApplyFilter /SaveAs C:\pm\trace.csv" -Wait
  while (Get-Process Procmon, Procmon64 -ErrorAction SilentlyContinue) { Start-Sleep 2 }
  Copy-Item C:\pm\trace*.pml, C:\pm\trace.csv $L -ErrorAction Continue
  foreach ($f in 'poll-net.txt','poll-procs.txt') { if (Test-Path "$L\$f") { Get-Content "$L\$f" | Sort-Object -Unique | Set-Content "$L\$f" } }
  ipconfig /displaydns | Set-Content "$L\dns-cache.txt"   # Get-DnsClientCache (WMI) wrote nothing in net-out
  wevtutil qe Microsoft-Windows-DNS-Client/Operational /f:text | Set-Content "$L\dns-client-events.txt"
  # the app's own settings and logs (e.g. whether the update check ran, or a canary turned up in its log);
  # they are discarded with the sandbox otherwise
  foreach ($d in "$env:APPDATA\VectorCraft", "$env:LOCALAPPDATA\VectorCraft") {
    if (Test-Path $d) { Copy-Item $d "$L\appdata-$(Split-Path (Split-Path $d) -Leaf)" -Recurse -Force -ErrorAction Continue } }
  Step 'observers stopped, trace saved'
}

function Install-VC {
  Step 'installing the MSI (silent)'
  $p = Start-Process msiexec.exe -ArgumentList "/i `"$MSI`" /qn /l*v `"$L\msi-install.log`"" -Wait -PassThru
  Step "msiexec exit code $($p.ExitCode)"
}
function Launch($argList) {
  Step "launch: vectorcraft $argList"
  if ($argList) { Start-Process $VC -ArgumentList $argList } else { Start-Process $VC }
}
function Close-VC { Ask 'Close VectorCraft normally (File > Quit or the X). Do NOT save anything.' }

# ============================ the probes ============================
Step "PROBE $Probe  (VectorCraft 0.17.0)"
$h = (Get-FileHash $MSI -Algorithm SHA256).Hash.ToLower()
Step "MSI sha256 $h"
if ($h -ne '861f4e9fe943dacddfd30bc6512a20a4db2fbc554a6daa4101595c2fc85d11c1') { Step 'MSI HASH MISMATCH - stopping'; Stop-Transcript; Read-Host; exit 1 }
Seed-Canaries

switch ($Probe) {
  'baseline' {     # network off. Install, launch, leave it alone for 2 minutes.
    Snapshot pre; Start-Watch; Install-VC; Launch
    Step 'idle 120 s - do not touch the app'; Start-Sleep 120
    Close-VC; Stop-Watch; Snapshot post; Diff-Snaps pre post }
  'install' {      # network off. The MSI only, no launch.
    Snapshot pre; Start-Watch; Install-VC; Stop-Watch; Snapshot post; Diff-Snaps pre post }
  'persist' {      # network off. Install + launch + quit, then look for anything set to start again.
    Snapshot pre; Install-VC; Snapshot installed; Start-Watch; Launch; Start-Sleep 60; Close-VC; Start-Sleep 15
    Stop-Watch; Snapshot post; Diff-Snaps pre installed; Diff-Snaps installed post }
  'net-out' {      # network ON. Startup update check; it is already the newest version, so no prompt expected.
    Install-VC; Start-Watch; Launch; Step 'running 120 s (startup update check)'; Start-Sleep 120
    Ask 'If an update prompt appeared, click Later. Then close VectorCraft.'; Stop-Watch }
  'self-update' {  # network ON, install dir writable. Pretend to be 0.1.0 so the real update is offered.
    Install-VC; Snapshot pre; Start-Watch
    $env:VECTORCRAFT_PRETEND_VERSION = '0.1.0'
    # net-out saw no update check at all, so the prompt may not come; "none appeared" is a result too
    Launch; Ask 'Wait up to 2 minutes for an update prompt. If one appears, click LATER. Either way, close VectorCraft. (Tell Claude whether a prompt appeared.)'
    Step 'second launch, still pretending 0.1.0'
    Launch; Ask 'If an update prompt appears, click UPDATE, wait until it has downloaded and restarted itself, then close it. If none appears within 2 minutes, just close VectorCraft.'
    Remove-Item Env:\VECTORCRAFT_PRETEND_VERSION
    Stop-Watch; Snapshot post; Diff-Snaps pre post
    & $VC --version 2>&1 | Set-Content "$L\version-after.txt"
    Get-AuthenticodeSignature $VC, $CLI | ForEach-Object { "$($_.Path): $($_.Status) / $($_.SignerCertificate.Subject)" } | Set-Content "$L\signature-after.txt"
    Get-FileHash $VC, $CLI | ForEach-Object { "$($_.Hash) $($_.Path)" } | Add-Content "$L\signature-after.txt" }
  'net-listen' {   # network off (loopback still works). Control server on 7979.
    Install-VC; Start-Watch; Launch '--control 7979'; Start-Sleep 15
    Get-NetTCPConnection -State Listen | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort) pid=$($_.OwningProcess) $((Get-Process -Id $_.OwningProcess).Name)" } |
      Set-Content "$L\listening.txt"
    Close-VC; Stop-Watch }
  'fs-read' {      # network off. Open one test file from the read-only tools folder.
    Install-VC; Start-Watch; Launch "`"$T\test.svg`""
    Ask 'Check that the test drawing opened. Then close VectorCraft WITHOUT saving.'; Stop-Watch }
  'fs-write' {     # network off. Export through the CLI into C:\probe\out, the only writable target.
    Install-VC; Start-Watch
    foreach ($ext in 'svg','pdf','png') {
      & $CLI convert "$T\test.svg" "C:\probe\out\test.$ext" 2>&1 | Add-Content "$L\cli-output.txt"; Step "exported test.$ext (exit $LASTEXITCODE)" }
    Stop-Watch
    Get-ChildItem C:\probe\out | ForEach-Object { "$($_.Name) $($_.Length)" } | Set-Content "$L\out-files.txt" }
  'exec' {         # network off. The three features that start other programs.
    Install-VC; Start-Watch; Launch "`"$T\test.svg`""
    Ask 'File > Print, choose "Microsoft Print to PDF", print, save the PDF to the Desktop.'
    Ask 'If there is a printer-setup / page-setup option, open it once and close it.'
    Ask 'If there is "Reveal in folder" / "Show in Explorer" (e.g. in File or the recent-files list), use it once.'
    Close-VC; Stop-Watch }
  'secrets' {      # network off. Ordinary use with fake credentials lying around.
    Install-VC; Start-Watch; Launch
    Ask 'Use the app normally for about 2 minutes: draw a few shapes, open every top menu, open and cancel the Open and Save dialogs.'
    Close-VC; Stop-Watch }
  'agent-text' {   # network off. Collect the text the MCP server gives an AI agent, for review on the host.
    Install-VC; Start-Watch
    $req = @(
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}',
      '{"jsonrpc":"2.0","method":"notifications/initialized"}',
      '{"jsonrpc":"2.0","id":2,"method":"tools/list"}',
      '{"jsonrpc":"2.0","id":3,"method":"prompts/list"}',
      '{"jsonrpc":"2.0","id":4,"method":"resources/list"}')
    Set-Content "$L\mcp-requests.jsonl" $req
    $p = Start-Process $CLI -ArgumentList 'mcp --headless' -RedirectStandardInput "$L\mcp-requests.jsonl" `
         -RedirectStandardOutput "$L\mcp-responses.jsonl" -RedirectStandardError "$L\mcp-stderr.txt" -NoNewWindow -PassThru
    if (-not $p.WaitForExit(30000)) { $p.Kill(); Step 'mcp server did not exit on end of input; killed after 30 s' }
    Stop-Watch }
  { $_ -like 'mcp-call-*' } {   # network off. Call the MCP tools for real; one pass per session:
                                # mcp-call-unscoped (A), mcp-call-scoped (B, with the automation roots);
                                # mcp-call-commands / -links (probe 13): the roots against command ids and links
    $pass = $Probe -replace '^mcp-call-', ''
    # an extra canary only an SVG reader would open, so a refusal can't just be "unsupported file type"
    $tag = Get-Content "$L\canary-tag.txt"; $docs = [Environment]::GetFolderPath('MyDocuments')
    $cs = Join-Path $docs 'canary-drawing.svg'; New-Item -ItemType Directory -Force $docs | Out-Null
    Set-Content $cs "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"10`" height=`"10`"><title>$tag-svg</title><rect width=`"10`" height=`"10`"/></svg>"
    Add-Content "$L\canary-paths.txt" $cs
    $desk = [Environment]::GetFolderPath('Desktop'); New-Item -ItemType Directory -Force $desk | Out-Null
    Step "extra canary $cs; desktop is $desk"
    Install-VC
    New-Item -ItemType File -Force "$L\empty.txt" | Out-Null
    $hp = Start-Process $CLI -ArgumentList 'mcp --help' -RedirectStandardInput "$L\empty.txt" -RedirectStandardOutput "$L\mcp-help.txt" `
          -RedirectStandardError "$L\mcp-help-stderr.txt" -NoNewWindow -PassThru
    if (-not $hp.WaitForExit(15000)) { $hp.Kill(); Step 'mcp --help did not exit; killed after 15 s' }
    if ($pass -eq 'links') {   # roots on the sandbox's own disk, so no link is ever made in a host-mapped folder
      New-Item -ItemType Directory -Force C:\work\in, C:\work\out | Out-Null
      Copy-Item "$T\test.svg" C:\work\in\
      & { cmd /c mklink "C:\work\in\canary-link.svg" "$cs"
          cmd /c mklink /J "C:\work\in\win-junction" "C:\Windows"
          cmd /c mklink /J "C:\work\out\desk-junction" "$desk" } 2>&1 | Set-Content "$L\links-made.txt"
      Get-ChildItem C:\work\in, C:\work\out -Force | ForEach-Object { "$($_.FullName) [$($_.Attributes)] -> $($_.Target)" } | Add-Content "$L\links-made.txt"
      Step 'links made under C:\work (links-made.txt)'
    }
    Start-Watch
    function Run-Pass($name, $argList, $calls) {
      $lines = @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}',
                 '{"jsonrpc":"2.0","method":"notifications/initialized"}')
      $labels = @(); $id = 1
      foreach ($c in $calls) {
        $id++
        $lines += (@{ jsonrpc = '2.0'; id = $id; method = 'tools/call'; params = @{ name = $c[0]; arguments = $c[1] } } | ConvertTo-Json -Compress -Depth 10)
        $labels += "$id $($c[0]) $($c[2])"
      }
      Set-Content "$L\mcp-requests-$name.jsonl" $lines
      Set-Content "$L\mcp-labels-$name.txt" $labels
      Step "pass $name : vectorcraft-cli $argList ($($calls.Count) tool calls)"
      $p = Start-Process $CLI -ArgumentList $argList -RedirectStandardInput "$L\mcp-requests-$name.jsonl" `
           -RedirectStandardOutput "$L\mcp-responses-$name.jsonl" -RedirectStandardError "$L\mcp-stderr-$name.txt" -NoNewWindow -PassThru
      Step "pass $name server pid $($p.Id)"
      if (-not $p.WaitForExit(60000)) { $p.Kill(); Step "pass $name : server did not exit on end of input; killed after 60 s" }
      else { Step "pass $name : server exit code $($p.ExitCode)" }
    }
    $rect  = @{ shape = 'rectangle'; x = 100; y = 100; width = 200; height = 120 }
    $paint = @{ fill = '#3366cc'; stroke = '#000000'; strokeWidth = 2 }
    $common = { param($exp) @(
      ,@('run_command', @{ command = 'file.new'; params = @{ width = 800; height = 600 } }, 'new document')
      ,@('draw_shape', $rect, 'rectangle')
      ,@('set_paint', $paint, 'paint on selection')
      ,@('doc_inspect', @{}, 'document summary')
      ,@('render_preview', @{ max_side = 256 }, 'inline png')
      ,@('export', @{ path = $exp }, 'in-root export')
      ,@('open_file', @{ path = "$T\test.svg" }, 'in-root open')) }
    $scopedArgs = "mcp --headless --automation-read-root $T --automation-write-root C:\probe\out"
    if ($pass -eq 'unscoped') { Run-Pass 'unscoped' 'mcp --headless' ((& $common 'C:\probe\out\a.svg') + @(
      ,@('export', @{ path = "$desk\control.svg" }, 'CONTROL out-of-root export, unscoped'))) }
    elseif ($pass -eq 'commands') {
      # 1. discovery, read-only
      Run-Pass 'discovery' $scopedArgs @(foreach ($f in 'open','save','export','place','import') { ,@('command_list', @{ filter = $f; brief = $true }, "filter $f") })
      $found = @()
      foreach ($line in Get-Content "$L\mcp-responses-discovery.jsonl") {
        # PS 5.1's ConvertFrom-Json hands back a JSON array as one object: enumerate it explicitly
        try { $o = ConvertFrom-Json $line
              if ($o.result.content) { $arr = ConvertFrom-Json $o.result.content[0].text
                if ($arr -isnot [array] -and $arr.commands) { $arr = $arr.commands }   # list_commands shape {count, commands}
                foreach ($x in $arr) { $found += $x } } } catch { Step "discovery reply not parsed: $_" }
      }
      # 2. the selection rule approved in probe-plan.md (probe 13)
      $inc = 'open|save|export|place|import'; $exc = 'print|reveal|recent|revert|close|quit|browse|dialog|url|web|package'
      $pick = @('document.save', 'document.export')
      foreach ($c in $found) {
        $txt = "$($c.id) $($c.label)"
        if ($pick.Count -ge 8) { break }
        if ($c.id -and $txt -match $inc -and $txt -notmatch $exc -and $pick -notcontains $c.id) { $pick += $c.id }
      }
      $found | ForEach-Object { "$($_.id) | $($_.label) | $($_.menu)" } | Sort-Object -Unique | Set-Content "$L\commands-found.txt"
      Set-Content "$L\commands-chosen.txt" $pick
      Step "commands chosen: $($pick -join ', ')"
      # 3. each chosen command: in-root control, then out of root, by four routes
      $calls = @(,@('run_command', @{ command = 'file.new'; params = @{ width = 800; height = 600 } }, 'new document')
                 ,@('draw_shape', $rect, 'rectangle'))
      $n = 0
      foreach ($cmd in $pick) {
        $n++
        $isRead = ($cmd -match 'open|place|import') -and ($cmd -notmatch 'save|export')
        if ($isRead) { $tries = @(@("$T\test.svg", 'IN'), @($cs, 'OUT canary svg'), @('C:\Windows\win.ini', 'OUT win.ini')) }
        else { $tries = @(@('C:\probe\out\cmd-{0}-{1}.svg', 'IN'), @("$desk\cmd-{0}-{1}.svg", 'OUT Desktop')) }
        foreach ($route in 'run_command', 'command_run', 'command_batch', 'invoke_menu') {
          foreach ($try in $tries) {   # not $t: names ignore case, and $T is the tools folder
            $path = $try[0] -f $n, $route
            $prm = @{ path = $path }
            $a = switch ($route) {
              'run_command'   { @{ command = $cmd; params = $prm } }
              'command_run'   { @{ id = $cmd; params = $prm } }
              'command_batch' { @{ steps = @(@{ id = $cmd; params = $prm }); stop_on_error = $false } }
              'invoke_menu'   { @{ command = $cmd; params = $prm } }
            }
            $calls += ,@($route, $a, "$($try[1]) $cmd $path")
          }
        }
      }
      Run-Pass 'commands' $scopedArgs $calls }
    elseif ($pass -eq 'links') {
      Run-Pass 'links' 'mcp --headless --automation-read-root C:\work\in --automation-write-root C:\work\out' @(
        ,@('run_command', @{ command = 'file.new'; params = @{ width = 800; height = 600 } }, 'new document')
        ,@('draw_shape', $rect, 'rectangle')
        ,@('export', @{ path = 'C:\work\out\a.svg' }, 'IN export')
        ,@('open_file', @{ path = 'C:\work\in\test.svg' }, 'IN open')
        ,@('open_file', @{ path = 'C:\work\in\canary-link.svg' }, 'OUT symlink to canary svg')
        ,@('open_file', @{ path = 'C:\work\in\win-junction\win.ini' }, 'OUT junction to C:\Windows')
        ,@('export', @{ path = 'C:\work\out\desk-junction\j.svg' }, 'OUT export through junction to Desktop')
        ,@('save_file', @{ path = 'C:\work\out\desk-junction\j.svg' }, 'OUT save through junction to Desktop')) }
    else { Run-Pass 'scoped' "mcp --headless --automation-read-root $T --automation-write-root C:\probe\out" ((& $common 'C:\probe\out\b.svg') + @(
      ,@('save_file', @{ path = 'C:\probe\out\b-saved.svg' }, 'in-root save')
      ,@('screenshot', @{ path = 'C:\probe\out\b.png' }, 'in-root screenshot')
      ,@('export', @{ path = "$desk\x.svg" }, 'OUT export to Desktop')
      ,@('save_file', @{ path = "$desk\x.vectorcraft" }, 'OUT save to Desktop')
      ,@('screenshot', @{ path = "$desk\x.png" }, 'OUT screenshot to Desktop')
      ,@('open_file', @{ path = $cs }, 'OUT open canary svg')
      ,@('open_file', @{ path = "$env:USERPROFILE\.ssh\id_rsa" }, 'OUT open canary id_rsa')
      ,@('open_file', @{ path = 'C:\Windows\win.ini' }, 'OUT open win.ini')
      ,@('export', @{ path = 'C:\probe\out\..\escape.svg' }, 'OUT traversal export')
      ,@('open_file', @{ path = "$T\..\..\Windows\win.ini" }, 'OUT traversal open win.ini'))) }
    Stop-Watch
    & { "== C:\probe\out"; Get-ChildItem C:\probe\out -Force | ForEach-Object { "$($_.Name) $($_.Length)" }
        "== C:\probe";     Get-ChildItem C:\probe -Force | ForEach-Object { "$($_.Name) $($_.Length)" }
        "== $desk";        Get-ChildItem $desk -Force | ForEach-Object { "$($_.Name) $($_.Length)" }
        '== out-of-root targets (exists?)'
        foreach ($f in "$desk\control.svg", "$desk\x.svg", "$desk\x.vectorcraft", "$desk\x.png", 'C:\probe\escape.svg') { "$(Test-Path $f) $f" }
        if ($pass -eq 'links') {
          '== C:\work\in'; Get-ChildItem C:\work\in -Force | ForEach-Object { "$($_.Name) $($_.Length) [$($_.Attributes)]" }
          '== C:\work\out'; Get-ChildItem C:\work\out -Force | ForEach-Object { "$($_.Name) $($_.Length) [$($_.Attributes)]" }
          "$(Test-Path "$desk\j.svg") $desk\j.svg" }
      } | Set-Content "$L\out-files.txt"
    if ($pass -eq 'links') {   # plain files only: copying the junction would follow it into the Desktop
      New-Item -ItemType Directory -Force "$L\work-out" | Out-Null
      Get-ChildItem C:\work\out -File -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        Copy-Item -Destination "$L\work-out\" }
  }
}

# no self-shutdown: a guest Stop-Computer left the host's Windows Sandbox window hung (fs-write), so a person
# closes the window, as for every other probe
Step 'PROBE FINISHED. Logs are in the host folder. Close this Sandbox window (all changes are discarded).'
Set-Content "$L\DONE.txt" (Get-Date)
Stop-Transcript | Out-Null
Read-Host 'Press Enter to close this console'
