# tinyraven firmware logo

Replaces the coreboot hare shown at `Ctrl+L` with the tinyraven mark. The logo is
compiled into the edk2 payload, so this means building that payload and writing
it to the `RW_LEGACY` firmware region. The stock firmware, write-protect and
ChromeOS are not touched.

**Status: prepared, never built, never flashed.** MrChromebox does not support
self-built `RW_LEGACY` payloads, and no report of a logo change on `RW_LEGACY`
was found (the known successes are on Full ROM).

## Steps

1. **Build**, on an x86_64 Arch Linux machine: `./build.sh`. The first run builds
   the toolchain (about an hour). Output: `~/build/tinyraven-firmware/rwl_tinyraven.bin`.
2. **Compare.** The script prints the layout of our image and of MrChromebox's
   published one. They must match in everything but the payload's size.
3. **Check the way back.** On the Chromebook, boot ChromeOS with `Ctrl+D` and
   confirm it starts. It is the recovery path.
4. **Flash**, on the Chromebook in Linux, on the charger:
   `./flash.sh backup`, then `./flash.sh flash rwl_tinyraven.bin`.
5. **Reboot**, `Ctrl+L`. The raven shows in place of the hare.

## If it goes wrong

- **`Ctrl+L` shows nothing or hangs.** Power off. Boot ChromeOS with `Ctrl+D`,
  open the text console (`Ctrl+Alt+F2`, user `chronos`), run MrChromebox's script
  and choose "Install/Update RW_LEGACY Firmware". That writes his image back.
- **The write fails before a reboot.** Run `./flash.sh restore` straight away.
- **flashrom cannot read the chip in Linux.** The kernel may block it; boot once
  with `iomem=relaxed` (see the message `flash.sh` prints). The first flash of
  this machine was done from ChromeOS, so the Linux path is untested here.
- **It cannot brick the Chromebook.** MrChromebox's docs on `RW_LEGACY`: "Carries
  zero risk of bricking the device". The cost of a bad image is the detour above.

## The logo

`logo.png`, 480×400, is cut from the centre of the boot splash as rendered on the
Chromebook (`../splash.svg`). edk2 draws the logo centred and unscaled, and the
firmware screen mode is 1366×768, so the firmware logo and the Linux boot splash
sit on the same pixels. To change it, redo the crop:

    magick bg.png -crop 480x400+443+184 +repage -alpha off PNG24:logo.png

## What is verified and what is not

Verified by reading the sources (November 2026):

- The build script, branch and logo option: `build-rwl_payload.sh` on
  `MrChromebox-2609`; Kconfig `EDK2_BOOTSPLASH_FILE`; the edk2 Makefile converts
  it with `convert ... BMP3:`.
- The published Gemini Lake image is 1,835,008 bytes and holds one CBFS file
  named `payload`. The stock octopus flash map gives `RW_LEGACY` that size.
- The flashrom build and options, from MrChromebox's `firmware.sh`.
- The firmware screen mode on this Chromebook is 1366×768 (the kernel's boot
  framebuffer).

Not verified:

- The `cbfstool` wrap in `build.sh`. It is inferred from the published image and
  from <https://github.com/hexdump0815/coreboot-cb-rw-uefi-payload>.
- That a logo larger than the stock 250×200 displays. edk2's code has no size
  limit below the screen size; if it fails, the boot goes on with no logo.
- That Arch's ImageMagick still provides `convert`.
- flashrom on kernel 7.2 without `iomem=relaxed`.
