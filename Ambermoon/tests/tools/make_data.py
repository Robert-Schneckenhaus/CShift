#!/usr/bin/env python3
# Writes the synthetic test data of Ambermoon/tests (no data of the game): files to pack, a 2D map with events and an
# NPC with events. Deterministic: the same files every time.
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
