#!/bin/bash
# The Pixel 10's boot image for one run: the Tensor G5's boot shim (socs/lga/shim: no UEFI, it starts the loader itself)
# and a payload with everything in it -- the loader, the kernel, the small root, the command line -- in an Android boot
# image of header v4 with an AVB hash footer (test key), for `fastboot boot`: the phone runs it from RAM and nothing is
# written to it. The run ends by itself after SECS seconds (loader_return_after=): the loader keeps its log in the
# ramoops RAM (0x95400000) and restarts the phone.
#
#   devices/frankel/mkimage.sh [-o xnu-frankel.img] [-k kernel] [-r root.apfs] [-s SECS] [-q] [-f BASE,W,H,STRIDE] [boot-args...]
#
# -f: the boot loader's framebuffer, once known (scion.fb= on the boot image's command line, read by the shim); without it
# the shim looks for it in the display controller (README.md, "Display"). The kernel is the Pixel's own configuration
# (make frankel_defconfig && make kernel: hakios-kernel); the boot-arguments default to that configuration's
# (tools/hakios-config.py args), with -v (the kernel's log on the screen) unless -q. The loader is xnuloader/loader.efi,
# built with the iPhone identity from your own IPSW (make loader): the image is yours, never to be published.
# mkxnuimg.py needs mkbootimg (AOSP) and, for the AVB footer, avbtool (AOSP external/avb): MKBOOTIMG=, AVBTOOL= or on PATH.
#
# This makes a file. It does not touch a phone: README.md says what running it takes (an unlocked boot loader: a wipe).
set -e
START=$PWD
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT=$ROOT/xnu-frankel.img K=$ROOT/hakios-kernel RD=$ROOT/userland/root.apfs SECS=120 VERBOSE=-v FB=
while getopts o:k:r:s:qf: opt; do
	case $opt in
	o) OUT=$OPTARG ;; k) K=$OPTARG ;; r) RD=$OPTARG ;; s) SECS=$OPTARG ;; q) VERBOSE= ;; f) FB=$OPTARG ;;
	*) sed -n 2,17p "$0"; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
abs() { case "$1" in /*) echo "$1" ;; *) echo "$START/$1" ;; esac; }
OUT=$(abs "$OUT") K=$(abs "$K") RD=$(abs "$RD")
L=xnuloader/loader.efi
for f in "$L" "$K" "$RD"; do
	[ -f "$f" ] || { echo "mkimage.sh: $f is missing (make loader, make kernel, userland/build.sh)" >&2; exit 1; }
done
[ -f socs/lga/shim/Makefile ] || { echo "mkimage.sh: no socs/lga (tools/hakios-device.py sync lga)" >&2; exit 1; }
make -s -C socs/lga/shim shim.bin
ARGS="$*"
if [ -z "$ARGS" ]; then
	# the arguments of the configuration made here, which must be this phone's (make frankel_defconfig)
	grep -q '^CONFIG_DEVICE="frankel"' .config 2>/dev/null || {
		echo "mkimage.sh: .config is not the Pixel 10's: make frankel_defconfig first, or give the boot-arguments" >&2; exit 1; }
	ARGS=$(python3 tools/hakios-config.py args)
fi
ARGS="${VERBOSE:+$VERBOSE }$ARGS"
P=$(mktemp "${TMPDIR:-/tmp}/frankel-payload.XXXXXX")
trap 'rm -f "$P"' EXIT
python3 xnuloader/mkpayload.py -o "$P" loader.efi="$L" kernel="$K" ramdisk="$RD" \
	--cmdline "loader_return_after=$SECS epoch=$(date +%s) $ARGS" >/dev/null
BOOT_CMDLINE="${FB:+scion.fb=$FB}" UEFI_TARGET=frankel python3 mkxnuimg.py -p "$P" -o "$OUT"
echo "mkimage.sh: $OUT; boot-args: $ARGS; the run returns after $SECS s"
echo "mkimage.sh: nothing was sent to a phone. Running it needs an unlocked boot loader, and unlocking wipes the phone (README.md)."
