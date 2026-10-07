#!/usr/bin/env python3
# Writes the synthetic test data of Ambermoon/tests (no data of the game): files to pack, a 2D map with events and an
# NPC with events, files for HexValueChanger, texts for the text packers and a folder in the layout of the Ambermoon
# repository for AmbermoonExtroIntroTextPackCreator. Deterministic: the same files every time.
#
#   python3 make_data.py <tests folder>
import os, random, sys

root = sys.argv[1]
r = random.Random(4711)

def write(path, data):
    path = os.path.join(root, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)

words = ('the a dragon amber moon sword shield of to and is in tower castle magic potion gold riddle mouth '
         'door chest key dungeon spell thief knight forest river ship horse').split()
def text(n):
    out = []
    while sum(len(w) + 1 for w in out) < n:
        out.append(r.choice(words))
    return ' '.join(out).encode()[:n]

# files to pack (002 has runs and repeats, 003 is random, 005 has an odd size, 006 is empty)
write('pack/files/001', text(3000))
runs = bytearray()
while len(runs) < 2500:
    k = r.random()
    if k < 0.3:
        runs += bytes([r.choice([0, 0, 0x55, 0xff])]) * r.randint(3, 300)
    elif k < 0.6 and len(runs) > 20:
        start = r.randint(0, len(runs) - 10)
        runs += runs[start:start + r.randint(3, 140)]
    else:
        runs += bytes(r.randint(0, 255) for _ in range(r.randint(1, 40)))
write('pack/files/002', bytes(runs[:2500]))
write('pack/files/003', bytes(r.randint(0, 255) for _ in range(777)))
write('pack/files/005', b'\x42')
write('pack/files/006', b'')
write('pack/textfiles/001', text(1500))
write('pack/textfiles/002', b'\x01\x02' + text(900))
for i in range(1, 4):
    write('pack/items/%03d' % i, bytes(r.randint(0, 255) for _ in range(60)))

# events: random data of all kinds, chains and branches
def events_block(count, chains):
    data = bytearray()
    starts = r.sample(range(count), chains)
    data += chains.to_bytes(2, 'big')
    for s in starts:
        data += s.to_bytes(2, 'big')
    data += count.to_bytes(2, 'big')
    for i in range(count):
        t = r.choice(list(range(1, 33)) + [1, 4, 12, 13, 14, 15, 19, 9, 2, 3])
        d = bytearray(r.randint(0, 255) if r.random() < 0.5 else r.randint(0, 6) for _ in range(9))
        if t in (2, 3, 13, 15, 19, 26):   # door, chest, condition, dice, decision, party member condition: a branch
            target = 0xffff if r.random() < 0.4 else r.randint(0, count - 1)
            d[7:9] = target.to_bytes(2, 'big')
        if t == 13:
            d[0] = r.randint(0, 0x1e)
        if t == 9:
            d[0] = r.randint(0, 0x16); d[1] = r.randint(0, 7); d[3] = r.choice([0, 1, 2, 3, 100, 105, 200, 203])
        if t == 7:
            d[0] = r.randint(0, 7)
        nxt = 0xffff if r.random() < 0.35 else r.randint(0, count - 1)
        data += bytes([t]) + bytes(d) + nxt.to_bytes(2, 'big')
    return bytes(data)

width, height = 8, 6
head = bytearray(r.randint(0, 255) for _ in range(0x14C))
head[2] = 2 # 2D map
head[4] = width
head[5] = height
tiles = bytearray()
for i in range(width * height):
    tiles += bytes([r.randint(0, 255), r.randint(0, 12), r.randint(0, 255), r.randint(0, 255)])
write('events/map/300', bytes(head) + bytes(tiles) + events_block(48, 12) + bytes(r.randint(0, 255) for _ in range(40)))
write('events/npc', bytes(r.randint(0, 255) for _ in range(0x122)) + events_block(30, 6))

# HexValueChanger: files of different sizes, one in a folder below
write('hex/files/a.bin', bytes(r.randint(0, 255) for _ in range(64)))
write('hex/files/b.bin', bytes(r.randint(0, 255) for _ in range(32)))
write('hex/files/c.txt', text(16))
write('hex/files/sub/d.bin', bytes(r.randint(0, 255) for _ in range(40)))

# text packers: texts in all the encodings that File.ReadAllText of .NET reads (byte order marks of UTF-8, UTF-16 and
# UTF-32), invalid UTF-8, line breaks, commands with and without a first text, folders that are left out
I = 'texts/IntroTexts/'
write(I + '000.txt', b'\xef\xbb\xbfBOM ' + text(20))
write(I + '001.txt', b'\xff\xfe' + 'UTF-16 LE: \u00e4\u00f6\u00fc \u20ac'.encode('utf-16-le'))
write(I + '002.txt', b'\xfe\xff' + 'BE \U0001F600 \ud800'.encode('utf-16-be', 'surrogatepass'))
write(I + '003.txt', b'bad \x80 \xc3 \xe2\x82 \xf0\x9f\x98 \xed\xa0\x80 \xc0\xaf \xf5 end\xe2')
write(I + '004.txt', b'line1\r\nline2\rline3\n')
write(I + '005.txt', b'')
write(I + '009.000.txt', text(30))
write(I + '010.000.txt', b'cmd a')
write(I + '010.001.txt', b'cmd b')
write(I + '011.002.txt', b'a command without .000')
write(I + '011.003.txt', text(12))
write(I + '012.000.txt', b'\xff\xfe\x00\x00' + 'UTF-32 \u00df'.encode('utf-32-le'))
write(I + '012.001.txt', b'\xff\xfe\x41')
E = 'texts/ExtroTextGroups/'
write(E + '000/000/000.txt', text(40))
write(E + '000/000/001.txt', b'e2 \xe4')
write(E + '000/001/000.txt', b'odd')
write(E + '002/000/000.txt', 'Gr\u00fc\u00dfe'.encode())
write(E + '002/003/010.txt', text(25))
write(E + '002/003/002.txt', text(7))
write(E + 'xyz/000.txt', b'left out')
write(E + 'end_texts/000.txt', b'left out')

# AmbermoonExtroIntroTextPackCreator: the language "Testish" in the layout of the Ambermoon repository
B = 'creator/Disks/Bugfixing/Testish/'
for i in range(15):
    write(B + 'IntroTexts/%03d.txt' % i, (b'\xef\xbb\xbf' if i == 3 else b'') + text(r.randint(5, 60)))
for c in range(6):
    for g in range(r.randint(1, 3)):
        for t in range(r.randint(1, 4)):
            write(B + 'ExtroTexts/%03d/%03d/%03d.txt' % (c, g, t), text(r.randint(3, 50)))
write(B + 'ExtroTexts/end_texts/000.txt', b'left out')
T = 'creator/Translations/Testish/'
write(T + 'click-text.txt', b'\xef\xbb\xbf \t<KLICK>\xc2\xa0\r\n')
write(T + 'translators.txt', '# translators\r\n  ANNA \u0160T\u011aP\u00c1NKOV\u00c1  \r\n\r\n   \n#X\nBOB B\rCARL'.encode())
