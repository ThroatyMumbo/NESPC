#!/usr/bin/env bash
# Build usbadapter and flash it: SWD through the adapter's own debugprobe, else picotool for a board in BOOTSEL.
# --no-build flashes the last build. USB_PROBE, OPENOCD and OPENOCD_SCRIPTS come from the environment or flash.env.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
build_dir="$here/build"
elf="$build_dir/usbadapter.elf"

do_build=1
for arg in "$@"; do
    case "$arg" in
        --no-build) do_build=0 ;;
        *) echo "usage: $0 [--no-build]" >&2; exit 2 ;;
    esac
done

if [ -f "$here/flash.env" ]; then
    set -a
    . "$here/flash.env"
    set +a
fi

if [ "$do_build" = 1 ]; then
    cmake -S "$here" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$build_dir" -j"$(nproc)"
fi

# the debugprobe's serial, required for SWD so another probe on the bench never gets this image
probe_serial="${USB_PROBE:-}"

if [ -n "$probe_serial" ] && compgen -G "/dev/serial/by-id/*Debugprobe*${probe_serial}*" >/dev/null; then
    # cold_reset, not "reset": openocd resets cm1 after cm0 is running, killing the core 1 that main launched
    "${OPENOCD:-openocd}" -f interface/cmsis-dap.cfg -c "adapter serial $probe_serial" -f target/rp2350.cfg \
        -c "adapter speed 5000" -c "program $elf verify" -c "cold_reset" -c "exit"
elif lsusb -d 2e8a:000f >/dev/null; then
    picotool load -v -x "$elf"
else
    echo "no debugprobe ${probe_serial:-(USB_PROBE unset)} and no RP2350 in BOOTSEL" >&2
    exit 1
fi
