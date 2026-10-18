#!/usr/bin/env python3
"""Fail the build when Desk code could run without its bank at $8000 (nes/conf/ld.cfg's bank areas), or names data
in another bank; `far` (include/desk.inc) is the way between banks. With --map, the bytes left in each RAM area."""
import argparse
import os
import re
import sys

SEGMENT = re.compile(r'\s*\.segment\s+"(\w+)"')
HEADER = re.compile(r'\b(?:DESK_BANK|DX_(?:MAGIC|FORMAT|API|DRAW|EVENT|NAME|IMAGE|RSRC))\b(?!_)')
FAR = re.compile(r'\s*far\s+(\w+)')
HOME = 'SHELL'  # the segment whose bank reset maps (src/exec.s shell_bank)
APP = 'app'
CFG = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'nes', 'conf', 'ld.cfg')


def attrs(body):
    return dict(m.groups() for m in re.finditer(r'(\w+)\s*=\s*([^,;]+?)\s*(?=[,;])', body + ';'))


def layout(cfg=CFG):
    """({memory: {attr: value}}, {segment: memory}) from ld.cfg"""
    text = re.sub(r'#.*', '', open(cfg).read())
    mems, segs = {}, {}
    for block, out in (('MEMORY', mems), ('SEGMENTS', segs)):
        body = re.search(block + r'\s*\{(.*?)\}', text, re.S).group(1)
        for name, rest in re.findall(r'(\w+)\s*:\s*([^;]*;)', body):
            out[name] = attrs(rest)
    return mems, {s: a.get('run', a['load']) for s, a in segs.items()}


def segment_banks(cfg=CFG):
    """{segment: bank} for the segments in banked memory areas"""
    mems, segs = layout(cfg)
    return {s: int(mems[m]['bank'], 0) for s, m in segs.items() if 'bank' in mems[m]}


def parse(paths):
    """procs {name: [segment, file:line, lines]}, tables {label: .word names}, JUMPS targets,
    data {label: segment} outside procs, aliases {name: expression}"""
    procs, tables, jumps, data, aliases = {}, {}, set(), {}, {}
    for path in paths:
        seg, cur, label = 'CODE', None, None
        for n, raw in enumerate(open(path), 1):
            line = raw.split(';')[0]
            if m := SEGMENT.match(line):
                seg = m.group(1)
            elif m := re.match(r'\s*\.proc\s+(\w+)', line):
                cur = m.group(1)
                procs[cur] = [seg, f'{path}:{n}', []]
            elif re.match(r'\s*\.endproc', line):
                cur = None
            elif cur:
                procs[cur][2].append(raw)
            elif seg == 'JUMPS':
                jumps.update(re.findall(r'\bjmp\s+(\w+)', line))
            elif m := re.match(r'(\w+)\s*=\s*(.+)', line):
                aliases[m.group(1)] = m.group(2)
            elif m := re.match(r'(\w+):', line):
                label = m.group(1)
                data[label] = seg
                if wm := re.match(r'\w+:\s*\.word\s+(.*)', line):
                    tables.setdefault(label, []).extend(re.findall(r'[A-Za-z_]\w*', wm.group(1)))
            elif label and (m := re.match(r'\s*\.word\s+(.*)', line)):
                tables.setdefault(label, []).extend(re.findall(r'[A-Za-z_]\w*', m.group(1)))
    return procs, tables, jumps, data, aliases


def data_banks(data, aliases, banks):
    """{label: bank} of the banked data, aliases included"""
    out = {k: banks[s] for k, s in data.items() if s in banks}
    for name, expr in aliases.items():
        for t in re.findall(r'[A-Za-z_]\w*', expr):
            if t in out:
                out[name] = out[t]
                break
    return out


def calls(name, procs, tables):
    """[(callee, far)] for every proc named in name's code or in a table it names, and the next when it falls through"""
    out = set()
    lines = procs[name][2]
    local = {m.group(1) for raw in lines if (m := re.match(r'\s*(\w+):', raw))}
    for raw in lines:
        code = raw.split(';')[0]
        if m := FAR.match(code):
            out.add((m.group(1), True))
            continue
        for t in re.findall(r'(?:\w+::)*([A-Za-z_]\w*)', code):
            if t in local:
                continue
            if t in procs:
                out.add((t, False))
            out.update((e, False) for e in tables.get(t, ()) if e in procs)
    if any('[fall_through]' in r for r in lines[-2:]):
        names = list(procs)
        out.add((names[names.index(name) + 1], False))
    return out


def check(paths, cfg=CFG):
    banks = segment_banks(cfg)
    procs, tables, jumps, data, aliases = parse(paths)
    dbank = data_banks(data, aliases, banks)
    home = banks[HOME]
    bank_of = {p: banks.get(seg) for p, (seg, _, _) in procs.items()}
    errors = []

    def where(b):
        return "a program's bank" if b == APP else f'bank {b}'

    roots = [(r, APP) for r in sorted(jumps | {'nmi'}) if r in procs]
    roots += [(r, home) for r in ('reset', 'main') if r in procs]
    roots += [(p, b) for p, b in bank_of.items() if b]
    stack, seen = [(p, b, [p]) for p, b in roots], set()
    while stack:
        p, ctx, path = stack.pop()
        if (p, ctx) in seen:
            continue
        seen.add((p, ctx))
        b = bank_of[p]
        if b is not None and b != ctx:
            errors.append(f"{procs[p][1]}: {p} is bank {b} code, reached with {where(ctx)} mapped: {' -> '.join(path)}")
            continue
        for c, far in calls(p, procs, tables):
            to = bank_of[c] if far and bank_of[c] else ctx
            stack.append((c, to, path + [('far ' if far else '') + c]))

    for p, (seg, at, lines) in procs.items():
        b = bank_of[p]
        for raw in lines:
            code = raw.split(';')[0]
            if FAR.match(code):
                continue
            if b and (m := HEADER.search(code)):
                errors.append(f"{at}: {p} uses {m.group(0)}, which needs the program's bank (src/exec.s app_bank)")
            for t in sorted(set(re.findall(r'[A-Za-z_]\w*', code)) & dbank.keys()):
                d = dbank[t]
                if d == 0 and b:
                    errors.append(f'{at}: {p} reads {t} in bank 0, which only gfx.s maps')
                elif d and d != b:
                    errors.append(f'{at}: {p} ({where(b) if b else "fixed"}) names {t}, which is in bank {d}')
    for e in dict.fromkeys(errors):
        print(e)
    counts = {}
    for b in bank_of.values():
        if b:
            counts[b] = counts.get(b, 0) + 1
    if not errors:
        print('bankcheck: ok, procs by bank ' + ', '.join(f'{b}: {n}' for b, n in sorted(counts.items())))
    return not errors


def room(map_path, cfg=CFG):
    """bytes left in each memory area holding RAM or a bank's code, from ld65's map"""
    mems, segs = layout(cfg)
    text = open(map_path).read()
    used = {}
    for name, start, end, size in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', text, re.M):
        if name in segs:
            used[segs[name]] = used.get(segs[name], 0) + int(size, 16)
    left = [f'{m} {int(a["size"].lstrip("$"), 16) - used.get(m, 0)}' for m, a in mems.items()
            if 'bank' in a and a.get('type') == 'rw' or a.get('file') == '""']
    print('bankcheck: bytes left: ' + ', '.join(left))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('sources', nargs='+')
    ap.add_argument('--map', help="ld65's map of the linked image, to report what is left")
    a = ap.parse_args()
    ok = check(a.sources)
    if ok and a.map:
        room(a.map)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
