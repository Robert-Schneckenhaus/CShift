# Evaluates the draft heuristic for .csh (CShift or Tcsh) on two corpora: real C shell scripts and the .csh files of
# the CShift repository. Prints the hits of every pattern and the result of the whole rule.
#   python -I evaluate.py <tcsh dir> <cshift repo>
import os
import re
import sys

# The patterns of the CShift rule (Ruby regexes in heuristics.yml; ^ and $ are line based there, re.M here).
PATTERNS = {
    'namespace': r'^[ \t]*namespace[ \t]+[A-Za-z_][\w.]*[ \t]*;',
    'using': r'^[ \t]*using[ \t]+[A-Za-z_][\w.]*[ \t]*;',
    'using-from': r'^[ \t]*using[ \t]+\w+[ \t]+from[ \t]+"',
    'type-decl': r'^[ \t]*(?:(?:public|static|unsafe|extern)[ \t]+)*(?:struct|interface|union|enum|error)[ \t]+[A-Z]\w*(?:<[\w, ]+>)?[ \t]*(?::[^\n{;]*)?(?:\{|$)',
    'const': r'^[ \t]*const[ \t]+[A-Za-z_][\w.]*(?:<[\w, <>]+>)?[ \t]+[A-Za-z_]\w*[ \t]*=',
    'main': r'^[ \t]*(?:int|void|Error<int>)[ \t]+Main[ \t]*\(',
    'function': r'^[ \t]*(?:static[ \t]+)?(?:void|int|bool|string|double|float|char|u?int(?:8|16|32|64)|[A-Z]\w*(?:<[\w, ]+>)?)[ \t]+[A-Za-z_]\w*[ \t]*\([^)\n]*\)[ \t]*$',
}


def read(path):
    with open(path, 'rb') as f:
        # as stored in git (and seen by Linguist): line ends are LF
        return f.read().decode('utf-8', errors='replace').replace('\r\n', '\n')


def files(root, skip_dirs=()):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs and not d.startswith('.')]
        for name in filenames:
            if name.endswith('.csh'):
                yield os.path.join(dirpath, name)


def evaluate(paths):
    hits = {k: [] for k in PATTERNS}
    matched = []
    for p in paths:
        text = read(p)
        any_hit = False
        for k, rx in PATTERNS.items():
            if re.search(rx, text, re.M):
                hits[k].append(p)
                any_hit = True
        if any_hit:
            matched.append(p)
    return hits, matched


tcsh = sorted(files(sys.argv[1]))
cshift = sorted(files(sys.argv[2], skip_dirs=('node_modules', 'bin', 'obj', 'build')))
th, tm = evaluate(tcsh)
ch, cm = evaluate(cshift)
print(f'{"pattern":<12} {"tcsh hits":>10} {"cshift hits":>12}')
for k in PATTERNS:
    print(f'{k:<12} {len(th[k]):>10} {len(ch[k]):>12}')
print(f'\nC shell scripts taken as CShift (false positives): {len(tm)} of {len(tcsh)}')
for p in tm:
    print('  FP', p)
missed = [p for p in cshift if p not in cm]
print(f'CShift files recognized: {len(cm)} of {len(cshift)}; missed: {len(missed)}')
for p in missed[:40]:
    print('  MISS', os.path.relpath(p, sys.argv[2]), '|', read(p).strip().split('\n')[0][:90])
