# trace-tree.py - runs on the HOST, on a probe's trace.csv (no Procmon needed). Usage: python -I trace-tree.py <trace.csv> <root image substring> <canary-paths.txt> [out.txt]
# Process tree of the root image from Process Create events, then that tree's footprint; canary hits by any process.
import csv, sys, re, collections
csv.field_size_limit(10**8)
src, root, canf = sys.argv[1:4]
out = open(sys.argv[4], 'w', encoding='utf-8') if len(sys.argv) > 4 else sys.stdout
canaries = [l.strip().lower() for l in open(canf, encoding='utf-8-sig') if l.strip()]
canaries.append('canary_token')
rows = []
with open(src, encoding='utf-8-sig', errors='replace', newline='') as f:
    r = csv.reader(f); next(r)
    for t, name, pid, op, path, res, det in r:
        if op in ('Process Create', 'Process Start') or root.lower() in name.lower() or root.lower() in path.lower() \
           or any(c in path.lower() or c in det.lower() for c in canaries) or name.lower() == 'msiexec.exe':
            rows.append((t, name, pid, op, path, res, det))
tree = {pid for t, name, pid, op, path, res, det in rows if root.lower() in name.lower()}
changed = True
while changed:
    changed = False
    for t, name, pid, op, path, res, det in rows:
        if op == 'Process Create' and pid in tree:
            m = re.search(r'PID: (\d+)', det)
            if m and m.group(1) not in tree: tree.add(m.group(1)); changed = True
p = lambda *a: print(*a, file=out)
p('tree pids:', sorted(tree))
p('== process creates by anything (child image, parent)')
for t, name, pid, op, path, res, det in rows:
    if op == 'Process Create': p(f'  {t} {name}({pid}) -> {path} | {det[:200]}')
mine = [x for x in rows if x[2] in tree]
p('== tree ops');
for k, v in collections.Counter((x[1], x[3]) for x in mine).most_common(): p(f'  {v:>7} {k}')
W = ('WriteFile', 'SetRenameInformationFile', 'SetDispositionInformationFile', 'SetDispositionInformationEx', 'SetEndOfFileInformationFile', 'SetBasicInformationFile')
p('== tree file writes / creates (unique paths)')
s = set()
for t, name, pid, op, path, res, det in mine:
    if op in W or (op == 'CreateFile' and res == 'SUCCESS' and re.search(r'Disposition: (Create|OverwriteIf|Overwrite|Supersede|OpenIf)', det) and 'Generic Write' in det):
        s.add((op, path))
for x in sorted(s): p('  ', *x)
p('== tree registry writes (unique keys)')
s = set()
for t, name, pid, op, path, res, det in mine:
    if op in ('RegSetValue', 'RegDeleteValue', 'RegDeleteKey', 'RegSetInfoKey') or (op == 'RegCreateKey' and 'REG_CREATED_NEW_KEY' in det):
        s.add((op, path, res))
for x in sorted(s): p('  ', *x)
p('== tree network events')
for t, name, pid, op, path, res, det in mine:
    if op.startswith(('TCP', 'UDP')): p(f'  {t} {name} {op} {path} {res}')
p('== tree files read outside install dir / Windows (unique, successful; mapped host folders included)')
s = set()
for t, name, pid, op, path, res, det in mine:
    lp = path.lower()
    # a mapped host folder shows as \Device\vmsmb\VSMB-{..}\<hash>\..., the sandbox's own Windows as ...\os\...
    mapped = lp.startswith('\\device\\vmsmb\\') and '}\\os\\' not in lp
    if op in ('CreateFile', 'ReadFile', 'QueryDirectory') and res == 'SUCCESS' and (mapped or (lp.startswith('c:\\') \
       and not lp.startswith(('c:\\windows\\', 'c:\\program files\\vectorcraft')))):
        s.add(path)
for x in sorted(s): p('  ', x)
p('== canary hits (any process)')
for t, name, pid, op, path, res, det in rows:
    if any(c in path.lower() or c in det.lower() for c in canaries): p(f'  {t} {name}({pid}) {op} {path} {res}')
p('== msiexec file writes outside Windows\\Installer, Temp (unique)')
s = set()
for t, name, pid, op, path, res, det in rows:
    if name.lower() == 'msiexec.exe' and op in W and not re.search(r'\\windows\\installer|\\temp\\|\\config\.msi', path.lower()):
        s.add(path.rsplit('\\', 1)[0])
for x in sorted(s): p('  ', x)
