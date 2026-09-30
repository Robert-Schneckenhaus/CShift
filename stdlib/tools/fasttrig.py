#!/usr/bin/env python3
# Generates the tables of stdlib/fasttrig.csh: python3 stdlib/tools/fasttrig.py > stdlib/fasttrig.csh
# (the text around the tables is in this script too).
import math

STEPS = 1024
IMAX = 2**31 - 1


def clamp(v):
    return max(-IMAX, min(IMAX, v))


def rows(values, per_line):
    lines = []
    for i in range(0, len(values), per_line):
        lines.append("    " + ", ".join(str(v) for v in values[i:i + per_line]))
    return ",\n".join(lines)


sin_table = [round(math.sin(2 * math.pi * i / STEPS) * 16384) for i in range(STEPS)]
tan_table = []
for i in range(STEPS // 2):
    if i == STEPS // 4:
        tan_table.append(IMAX)  # 90 degrees
    else:
        tan_table.append(clamp(round(math.tan(2 * math.pi * i / STEPS) * 65536)))
sec_table = []
for i in range(STEPS):
    c = math.cos(2 * math.pi * i / STEPS)
    if i == STEPS // 4 or i == 3 * STEPS // 4:
        sec_table.append(IMAX)  # 90 and 270 degrees
    else:
        sec_table.append(clamp(round(65536 / c)))
atan_table = [round(math.atan(i / 256) * STEPS / (2 * math.pi)) for i in range(257)]

print(open(__file__.replace("fasttrig.py", "fasttrig.head.txt")).read().rstrip("\n"))
print()
print("// sin in 1.14 for the angles 0..1023")
print("const ReadOnlySlice<int16> _SinTable = [\n" + rows(sin_table, 16) + "];")
print()
print("// tan in 16.16 for the angles 0..511 (tan repeats every 180 degrees)")
print("const ReadOnlySlice<int> _TanTable = [\n" + rows(tan_table, 8) + "];")
print()
print("// 1/cos in 16.16 for the angles 0..1023")
print("const ReadOnlySlice<int> _SecTable = [\n" + rows(sec_table, 8) + "];")
print()
print("// atan(i/256) in angle steps (0..128) for i = 0..256")
print("const ReadOnlySlice<int16> _AtanTable = [\n" + rows(atan_table, 16) + "];")
