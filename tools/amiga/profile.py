#!/usr/bin/env python3
"""Where an AmigaOS program spends its time: runs it under vamos (amitools) with the instruction trace and counts the
executed instructions of every function. The program must be built with -g, which writes the names of its functions
into the executable (HUNK_SYMBOL).

    cshiftc --target m68k-amigaos -g program.csh -o program
    python3 tools/amiga/profile.py [--cpu 68000] [--top 30] [--annotate NAME] program [arguments]

--annotate NAME also lists the instructions of the functions whose name contains NAME, each with how often it ran.
The trace is slow (about 30,000 instructions per second); the program's own output goes to stdout as usual.
"""
import argparse
import bisect
import collections
import re
import struct
import subprocess
import sys

HUNK_UNIT, HUNK_NAME, HUNK_CODE, HUNK_DATA, HUNK_BSS = 0x3E7, 0x3E8, 0x3E9, 0x3EA, 0x3EB
HUNK_RELOC32, HUNK_SYMBOL, HUNK_DEBUG, HUNK_END, HUNK_HEADER = 0x3EC, 0x3F0, 0x3F1, 0x3F2, 0x3F3


def code_symbols(path):
    """The symbols of the first code hunk: a sorted list of (offset, name)."""
    data = open(path, 'rb').read()
    pos = 0

    def long():
        nonlocal pos
        value = struct.unpack_from('>I', data, pos)[0]
        pos += 4
        return value

    if long() != HUNK_HEADER:
        sys.exit(f'{path}: not an AmigaOS executable')
    while long() != 0:  # resident libraries (none)
        pass
    long()  # number of hunks
    first, last = long(), long()
    for _ in range(last - first + 1):
        long()
    hunk = -1
    symbols = []
    while pos < len(data):
        kind = long() & 0x3FFFFFFF
        if kind in (HUNK_CODE, HUNK_DATA):
            hunk += 1
            size = long()
            pos += size * 4
        elif kind == HUNK_BSS:
            hunk += 1
            long()
        elif kind == HUNK_RELOC32:
            while True:
                count = long()
                if count == 0:
                    break
                pos += 4 + count * 4
        elif kind == HUNK_SYMBOL:
            while True:
                longs = long() & 0xFFFFFF
                if longs == 0:
                    break
                name = data[pos:pos + longs * 4].rstrip(b'\0').decode('utf-8', 'replace')
                pos += longs * 4
                offset = long()
                if hunk == 0:
                    symbols.append((offset, name))
        elif kind == HUNK_DEBUG:
            size = long()
            pos += size * 4
        elif kind == HUNK_END:
            pass
        else:
            sys.exit(f'{path}: unknown hunk type {kind:#x}')
    if not symbols:
        sys.exit(f'{path}: no symbols - build the program with -g')
    return sorted(symbols)


def main():
    parser = argparse.ArgumentParser(description='Instruction profile of an AmigaOS program under vamos.')
    parser.add_argument('--cpu', default='68000', help='68000 (default), 68020 or 68040')
    parser.add_argument('--top', type=int, default=30, help='the number of functions to list (default 30)')
    parser.add_argument('--annotate', metavar='NAME', help='list the instructions of the functions whose name contains NAME')
    parser.add_argument('program')
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()

    symbols = code_symbols(args.program)
    starts = [offset for offset, _ in symbols]
    command = ['vamos', '-v', '-I', '-C', args.cpu, args.program] + args.arguments
    process = subprocess.Popen(command, stderr=subprocess.PIPE, text=True, errors='replace')
    trace = re.compile(r'N/A\s+([0-9a-f]{6,8})\s{4}(.*)$')
    counts = collections.Counter()
    text = {}
    base = None
    cycles = None
    for line in process.stderr:
        m = trace.search(line)
        if m:
            pc = int(m.group(1), 16)
            if base is None:
                base = pc  # the first instruction is the start of the code hunk (the startup code)
            counts[pc] += 1
            if pc not in text:
                text[pc] = m.group(2).rstrip()
        elif 'total cycles:' in line:
            cycles = int(line.rsplit(':', 1)[1])
        elif 'instr:' not in line and ('ERROR' in line or 'WARNING' in line):
            sys.stderr.write(line)
    process.wait()
    if base is None:
        sys.exit('no instructions traced (is vamos installed: pip install amitools "machine68k<0.4"?)')

    def function_of(pc):
        i = bisect.bisect_right(starts, pc - base) - 1
        return symbols[i][1] if i >= 0 else '?'

    per_function = collections.Counter()
    calls = collections.Counter()
    entry = {base + offset: name for offset, name in symbols}
    for pc, n in counts.items():
        per_function[function_of(pc)] += n
        if pc in entry:
            calls[entry[pc]] += n
    total = sum(counts.values())
    print()
    print(f'{total} instructions' + (f', {cycles} cycles ({cycles / 7093790:.2f} s on an A500)' if cycles else ''))
    print(f'{"instructions":>12} {"share":>6} {"entries":>9}  function')
    for name, n in per_function.most_common(args.top):
        print(f'{n:12d} {100.0 * n / total:5.1f}% {calls[name]:9d}  {name}')

    if args.annotate:
        for offset, name in symbols:
            if args.annotate not in name or per_function[name] == 0:
                continue
            print(f'\n{name}')
            pcs = sorted(pc for pc in counts if function_of(pc) == name)
            for pc in pcs:
                print(f'{counts[pc]:10d}  {pc - base - offset:+06x}  {text[pc]}')
    return process.returncode


if __name__ == '__main__':
    sys.exit(main())
