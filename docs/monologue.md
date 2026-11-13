# Monologue: recording at 1080p30 on the Razer

Monologue (`github.com/omacom/monologue`, an Omarchy app) records the webcam through Qt Multimedia's FFmpeg backend. On the Razer (RTX 3070 Ti + Intel Iris Xe, i7-12800H, integrated 1080p MJPEG webcam) release 0.3.1 recorded at 5–16 fps or aborted the take. This page records what was wrong, what upstream already fixed, and what AerisOS still does. Investigated 2026-11-13.

## Files

| File | Job |
|---|---|
| `bin/monologue` | Wrapper installed to `~/.local/bin/monologue`, shadowing `/usr/bin/monologue`. Holds the webcam at 30 fps; on 0.3.x also applies the encoder workarounds below. |
| `omacom/x264-fast.c` | `LD_PRELOAD` shim, built to `~/.local/lib/x264-fast.so` by `./setup.sh omacom`. Forces libx264 preset `veryfast` (override: `MONOLOGUE_X264_PRESET`), only in a process named `monologue`, so the ffmpeg that Monologue runs for exports is untouched. |
| `setup.sh` `omacom_app` / `monologue_extras` | Builds the app from omarchy-pkgs (see below), builds the shim, writes `~/.local/share/applications/monologue.desktop` pointing at the wrapper. |
| `hyprland.lua` | Win+Shift+7 runs `~/.local/bin/monologue` by full path: Hyprland's PATH has no `~/.local/bin`. |

## What was wrong in 0.3.1

Each symptom, its cause and how it showed in the log (`monologue` from a terminal; launched from Hyprland, stderr goes to `journalctl --user`, but FFmpeg's own lines do not).

1. **Most video frames lost, ~5 fps.** Qt tried the hardware encoders in order. `h264_nvenc` failed (`10 bit encode not supported`), VA-API failed (`Cannot find software target format. sourceSWFormat: bgra targetFormat: vaapi`), `h264_qsv` opened. QSV's B-frames reached the MP4 muxer with non-monotonic DTS (`Application provided invalid, non monotonically increasing dts to muxer in stream 1`, `Failed to write packet`) and every such packet was dropped: 51 of 150 frames kept in a synthetic test.
2. **NVENC refused.** Monologue fed Qt BGRA frames; for RGB input Qt asks the encoder for a high-bit-depth 4:4:4 format, which H.264 NVENC rejects. Plain `ffmpeg -c:v h264_nvenc` works on the same machine for `bgra`, `yuv444p` and `yuv420p`.
3. **"Video encoding cannot keep up", take aborted.** With hardware excluded, Qt opened libx264 at its default preset `medium` with 4:4:4 input (`profile High 4:4:4 Predictive`, ~28 Mbit/s). On noisy 1080p webcam frames that encodes ~27 fps here, under the camera's 30. Preset `veryfast` does ~94 fps. Qt's API has no preset knob, hence the shim.
4. **~15 fps in dim light.** The camera's `exposure_dynamic_framerate=1` lets it halve the frame rate to lengthen exposure. The wrapper sets it to 0 (darker picture in a dim room).
5. **Raw takes are 4:4:4.** Not a fault once exported: Monologue's export runs its own `ffmpeg -c:v libx264 -preset veryfast -pix_fmt yuv420p`, so files saved to `~/Videos` play everywhere. Only the takes kept in `~/.local/share/omacom/monologue/recordings/` were 4:4:4, which also made the preview's CUDA decoder fail (`Hardware is lacking required capabilities`, falls back to software).

The camera's own ceiling is 30 fps in every MJPEG mode (1080p down to 320×180); YUYV runs 5 fps at 1080p. `/dev/video2` is the infrared Windows Hello sensor (GREY 640×360, 15 fps).

Harmless lines in the log: `qrc:/monologue.svg` not found, `QWaylandTextInputv3::disableSurface`, `Packet with invalid duration … in stream 1` from libx264's B-frames (all frames still written), the QML `Parameter "position" is not declared` deprecation.

## What upstream fixed after 0.3.1

Monologue 0.4.0 (tag `v0.4.0`) contains:

- #32 "Hand the encoder 8-bit 4:2:0 so NVENC records 4K webcams": `src/writer.cpp` converts MJPEG/YUYV/RGB frames to YUV420P before Qt sees them. This removes causes 2, 3 and 5 at the source and lets NVENC work.
- #37: `QT_FFMPEG_{ENCODING,DECODING}_HW_DEVICE_TYPES` default to `cuda,vaapi` (set only when unset, in `media::useFfmpeg()`), so QSV is not reached on this machine.
- #10 (no dropped frames on camera jitter), #19 (skip camera modes slower than 15 fps), #40 (skip truncated MJPEG frames).

The wrapper therefore applies the encoder workarounds only when the installed version is below 0.4.0 (`vercmp`). It must not set `QT_FFMPEG_ENCODING_HW_DEVICE_TYPES` on 0.4.0: upstream honors an already-set value and would lose NVENC.

## Why the machine still had 0.3.1

Monologue moved its packaging to `github.com/omacom/omarchy-pkgs` on 2026-11-12 (#31) and dropped `pkgbuild/PKGBUILD`. `omacom_app` ran `makepkg` in the app repo's `pkgbuild/`, which failed with only a warning, so `aeris-update` kept pulling the source while the installed package stayed at 0.3.1. `omacom_app` now falls back to a sparse clone of omarchy-pkgs (`~/.local/src/omarchy-pkgs`) when the app repo has no PKGBUILD.

## VA-API: the Qt bug (found on tinyraven, 2026-11-13)

The VA-API line in cause 1 is a Qt 6.12.0 bug, not a driver one. `findTargetSWFormat()` in `qffmpegvideoencoderutils.cpp` intersects the codec's declared pixel formats with VA-API's `valid_sw_formats`. `h264_vaapi` declares only `AV_PIX_FMT_VAAPI`, so the intersection is always empty and every Qt app falls back to libx264 on Intel and AMD. A ~20-line backport fixes it: on tinyraven, takes use `h264_vaapi`, no longer stop, and CPU drops from ~100% to ~50%. The patched packages (qt6-multimedia pkgrel 1.1) were built in `~/build/qt6-multimedia` on rzr and are not installed here; keep that directory and `~/build/vkh`. This is the report for Qt upstream; the findings also go to omacom/monologue issue #8.

## Still open

- Verify on 0.4.0 that NVENC is used and 1080p30 records without the shim; then the 0.3.x branch of the wrapper and `omacom/x264-fast.c` can go.
- Upstream candidates, not yet reported: the Qt Multimedia QSV non-monotonic DTS drop (a Qt bug, independent of Monologue; reproduce with a `QVideoFrameInput` + `QMediaRecorder` program pushing 150 BGRA 1080p frames with `QT_FFMPEG_ENCODING_HW_DEVICE_TYPES` unset and counting packets with `ffprobe -count_packets`), and Qt picking a >8-bit format for NVENC from RGB input. Monologue itself needs no report: 0.4.0 covers it.
