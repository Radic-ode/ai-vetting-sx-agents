# make-pmc.py - runs on the HOST. Writes tools/probe.pmc, the Process Monitor config every probe loads.
# Needs procmon-parser (pip, MIT). Run it from a venv outside this folder:
#   <venv>/python -I make-pmc.py
# The filter only drops noise Procmon itself would hide by default (its own events, NTFS metadata, fast
# I/O, profiling). It never filters by the component's name: anything VectorCraft starts must still show.
# DestructiveFilter=1 means dropped events are never written, which keeps the trace small enough to close.
import sys
from pathlib import Path
from procmon_parser import Column, Rule, RuleAction, RuleRelation, dumps_configuration, loads_configuration

EX, IS, BEGINS, ENDS, CONTAINS = RuleAction.EXCLUDE, RuleRelation.IS, RuleRelation.BEGINS_WITH, RuleRelation.ENDS_WITH, RuleRelation.CONTAINS
# Windows' own background scanners (Defender, Search, telemetry) react to every file the MSI writes.
# VectorCraft cannot be any of them, and anything it starts has another name, so dropping them loses nothing.
# 'System' is NOT dropped: in net-out, Procmon booked a service's TCP traffic under System and it went missing.
rules = [Rule(Column.PROCESS_NAME, IS, p, EX) for p in
         ('Procmon.exe', 'Procmon64.exe', 'MsMpEng.exe', 'NisSrv.exe', 'SearchIndexer.exe',
          'SearchProtocolHost.exe', 'SearchFilterHost.exe', 'CompatTelRunner.exe')]
rules += [
    Rule(Column.OPERATION, BEGINS, 'IRP_MJ_', EX),
    Rule(Column.OPERATION, BEGINS, 'FASTIO_', EX),
    Rule(Column.RESULT, BEGINS, 'FAST IO', EX),
    Rule(Column.EVENT_CLASS, IS, 'Profiling', EX),
    Rule(Column.PATH, ENDS, 'pagefile.sys', EX),
    Rule(Column.PATH, CONTAINS, '$Extend', EX),
]
rules += [Rule(Column.PATH, ENDS, m, EX) for m in
          ('$Mft', '$MftMirr', '$LogFile', '$Volume', '$AttrDef', '$Root', '$Bitmap', '$Boot', '$BadClus', '$Secure', '$UpCase')]

config = {
    'FilterRules': rules,
    'HighlightRules': [],
    'DestructiveFilter': 1,
    'Profiling': 0,
}
data = dumps_configuration(config)
back = loads_configuration(data)
assert back['FilterRules'] == rules and back['DestructiveFilter'] == 1, 'round trip failed'

out = Path(__file__).parent / 'tools' / 'probe.pmc'
out.write_bytes(data)
print(f'wrote {out} ({len(data)} bytes, {len(rules)} rules)')
for r in rules:
    print(' ', r)
