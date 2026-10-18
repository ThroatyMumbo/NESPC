#!/usr/bin/env python3
"""Host side of the mapper 773 tap (0x1802000+n), over edn8.py."""
import argparse, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..'))
from edn8 import EDN8  # noqa: E402

TAP = 0x1802000
PAD = TAP + 0x10  # ORed into pad 1 by the NES ($5008)
BEAT = TAP + 0x14  # the heartbeat ($5009, rtl/map_desk.sv)
MENU_RET = TAP + 0x1FFF  # $5007 bit 7: Desk hands the cart to the OS
BUTTONS = ['right', 'left', 'down', 'up', 'start', 'select', 'b', 'a']  # bit order, as nes/include/desk.inc


def cmd_menu(ed, a):
    try:
        ed.menu_test()
        print("menu already up")
        return
    except IOError:
        pass
    before = ed.mapper()
    ed.mem_wr(MENU_RET, b'\x01')
    t0 = time.time()
    # an OS that boots Desk reads MCU replies off the FIFO a '*t' would land in: probe once it has acked
    # (mapper 255, or 0 mid-load) and Desk (773) is configured; a 773 program before it looks the same
    while time.time() - t0 < 1 and ed.mapper() == before:
        time.sleep(0.02)
    while time.time() - t0 < 3 and ed.mapper() != 773:
        time.sleep(0.1)
    while time.time() - t0 < 20:  # the menu has been seen taking over 10 s to come back
        try:
            ed.menu_test()
            print("back in the menu")
            return
        except IOError:
            pass
    sys.exit("menu did not come back (core without menu_ret, or the NES program is not polling $5007)")


def cmd_status(ed, a):
    t0 = time.time()
    want = a.id.encode()
    while ed.mapper() != a.mapper or ed.mem_rd(TAP, 4) != want:
        if time.time() - t0 > 10:
            sys.exit(f"{a.id} on mapper {a.mapper} is not running (mapper {ed.mapper()}, id {ed.mem_rd(TAP, 4)!r})")
        time.sleep(0.1)
    # the heartbeat: Desk's starts after its boot has read the card, which a '*t' sent sooner would land among the
    # MCU's replies to
    beat = ed.mem_rd(BEAT, 1)
    while ed.mem_rd(BEAT, 1) == beat:
        if time.time() - t0 > 20:
            sys.exit(f"{a.id} is loaded but its heartbeat (tap 0x14) is stuck at {beat.hex()}")
        time.sleep(0.05)
    if a.id != 'DESK':  # apps don't answer '*t'
        print(f"{a.id} running ({time.time() - t0:.1f} s)")
        return
    while True:
        try:
            ed.menu_test()
            break
        except IOError:
            if time.time() - t0 > 20:
                sys.exit("mapper 773 is up but Desk doesn't answer *t")
    print(f"desk running ({time.time() - t0:.1f} s)")


def cmd_pad(ed, a):
    bits = sum(1 << BUTTONS.index(b) for b in a.buttons)
    ed.mem_wr(PAD, bytes([bits]))
    time.sleep(a.frames / 60)
    ed.mem_wr(PAD, b'\x00')
    time.sleep(0.05)  # released for a few frames, so the next press is new


def cmd_start(ed, a):
    ed.fifo_send(b'*w')


def cmd_open(ed, a):
    path = a.path.encode('latin-1')
    ed.fifo_send(b'*o' + len(path).to_bytes(2, 'little') + path)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port')
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('status', help='wait for Desk, or an app (--id, --mapper), to come up')
    p.add_argument('--id', default='DESK', help="the 4 letters at tap 0-3")
    p.add_argument('--mapper', type=int, default=773)
    sub.add_parser('menu', help='return the cart to its menu (no-op if already there)')
    sub.add_parser('start', help="press Desk's Windows key: the Start menu opens, or shuts if open")
    p = sub.add_parser('open', help="open a program (.dx) or follow a shortcut (.lnk), as the Start menu does")
    p.add_argument('path', help="its path on the card, e.g. nespc/system/display.dx or 'nespc/desktop/Game.lnk'")
    p = sub.add_parser('pad', help='hold buttons on pad 1 from the host')
    p.add_argument('buttons', nargs='+', choices=BUTTONS)
    p.add_argument('--frames', type=int, default=3)
    a = ap.parse_args()
    ed = EDN8(a.port)
    try:
        {'status': cmd_status, 'menu': cmd_menu, 'pad': cmd_pad, 'start': cmd_start, 'open': cmd_open}[a.cmd](ed, a)
    finally:
        ed.close()


if __name__ == '__main__':
    main()
