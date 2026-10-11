#!/usr/bin/env python3
# (c) Vladimir Garenitsa (MalwareDante), 2026. Original work.
"""HEIF box-structure mutator: generates structurally-valid-but-weird variants
from corpus files. Byte fuzzers struggle with container structure (size fields,
box ordering, nesting); this mutator recombines at the box level.

Usage: box_mutator.py <corpus_dir> <out_dir> <count> [seed]
"""
import os, random, struct, sys

def parse_boxes(buf, start=0, end=None):
    """Return list of (start, total_size, fourcc) top-level boxes."""
    if end is None:
        end = len(buf)
    boxes = []
    pos = start
    while pos + 8 <= end:
        size, fourcc = struct.unpack_from('>I4s', buf, pos)
        hdr = 8
        if size == 1 and pos + 16 <= end:
            size = struct.unpack_from('>Q', buf, pos + 8)[0]
            hdr = 16
        elif size == 0:
            size = end - pos
        if size < hdr:
            break
        boxes.append((pos, size, fourcc))
        pos += size
    return boxes

CONTAINERS = {b'meta': 4, b'moov': 0, b'trak': 0, b'minf': 0, b'dinf': 0,
              b'iprp': 0, b'ipco': 0, b'grpl': 0, b'ipro': 4, b'sinf': 0}

def iter_all_boxes(buf):
    """Recursively list (start, size, fourcc) including container children."""
    def rec(start, end, depth):
        end = min(end, len(buf))
        for (pos, size, fc) in parse_boxes(buf, start, end):
            yield (pos, size, fc)
            if depth < 3 and fc in CONTAINERS:
                child_start = pos + 8 + CONTAINERS[fc]
                if fc == b'meta' and size >= 12:
                    child_start = pos + 12
                child_end = min(pos + size, end)
                if child_start + 8 <= child_end:
                    yield from rec(child_start, child_end, depth + 1)
    yield from rec(0, len(buf), 0)

def mutate(buf, rng):
    boxes = list(iter_all_boxes(buf))
    if not boxes:
        return None
    op = rng.randrange(7)
    pos, size, fc = rng.choice(boxes)
    if op == 0:  # drop a box (recompute parent sizes is complex; drop whole top-level)
        tops = parse_boxes(buf)
        if len(tops) < 2:
            return None
        tpos, tsize, _ = rng.choice(tops)
        return buf[:tpos] + buf[tpos + tsize:]
    if op == 1:  # duplicate a box and re-append
        return buf + buf[pos:pos + size]
    if op == 2:  # corrupt this box's declared size
        delta = rng.choice([-1, 1, rng.randrange(-32, 4096)])
        newsize = size + delta
        if not (8 <= newsize <= 0xFFFFFFFF):
            return None
        nb = bytearray(buf)
        struct.pack_into('>I', nb, pos, newsize)
        return bytes(nb)
    if op == 3:  # truncate inside box payload
        cut = rng.randrange(pos + 8, pos + size) if size > 8 else pos + 8
        return buf[:cut]
    if op == 4:  # reorder top-level boxes
        tops = parse_boxes(buf)
        if len(tops) < 2:
            return None
        parts = [buf[p:p + s] for p, s, _ in tops]
        rng.shuffle(parts)
        tail = buf[tops[-1][0] + tops[-1][1]:]
        return b''.join(parts) + tail
    if op == 5:  # swap payloads of two boxes
        if len(boxes) < 2:
            return None
        (p1, s1, f1), (p2, s2, f2) = rng.sample(boxes, 2)
        nb = bytearray(buf)
        nb[p1 + 8:p1 + s1], nb[p2 + 8:p2 + s2] = nb[p2 + 8:p2 + s2], nb[p1 + 8:p1 + s1]
        return bytes(nb)
    # op == 6: inject a well-known fourcc box with random small payload
    known = [b'meta', b'pitm', b'iloc', b'iinf', b'infe', b'iprp', b'ipco',
             b'ipma', b'ispe', b'pixi', b'hvcC', b'av1C', b'mini', b'iref',
             b'idat', b'colr', b'clap', b'irot', b'imir', b'grid', b'iovl',
             b'mdat', b'thmb', b'auxC', b'dimg', b'cdsc', b'tmap',
             b'moov', b'mvhd', b'trak', b'tkhd', b'mdia', b'mdhd', b'minf',
             b'stbl', b'stsd', b'stts', b'stsc', b'stsz', b'stco', b'ctts',
             b'stss', b'sdtp', b'sgpd', b'sbgp', b'saiz', b'saio', b'tref',
             b'edts', b'elst', b'dinf', b'dref', b'vmhd', b'smhd', b'urim',
             b'vide', b'auxv', b'pict']
    fc = rng.choice(known)
    payload = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 64)))
    box = struct.pack('>I4s', 8 + len(payload), fc) + payload
    ins = rng.randrange(len(buf) + 1)
    return buf[:ins] + box + buf[ins:]

def main():
    cdir, odir, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
    rng = random.Random(int(sys.argv[4]) if len(sys.argv) > 4 else None)
    os.makedirs(odir, exist_ok=True)
    files = [os.path.join(cdir, f) for f in os.listdir(cdir)
             if os.path.isfile(os.path.join(cdir, f))]
    made = 0
    attempts = 0
    while made < count and attempts < count * 4:
        attempts += 1
        src = rng.choice(files)
        try:
            buf = open(src, 'rb').read()
        except OSError:
            continue
        if not buf or len(buf) > 1024 * 1024:
            continue
        out = mutate(buf, rng)
        if not out:
            continue
        with open(os.path.join(odir, 'bx%05d.bin' % made), 'wb') as f:
            f.write(out)
        made += 1
    print(f'mutator: {made} variants -> {odir}')

if __name__ == '__main__':
    main()
