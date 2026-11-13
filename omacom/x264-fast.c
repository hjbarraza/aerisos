// LD_PRELOAD shim for Monologue (Qt Multimedia FFmpeg backend): Qt opens libx264 at the
// default "medium" preset with 4:4:4 input, too slow for a 1080p30 webcam on this CPU
// ("encoding cannot keep up"). Force a faster preset, only inside the monologue process.
// Built into ~/.local/lib/x264-fast.so by `./setup.sh omacom`; loaded only by bin/monologue, and
// only for Monologue 0.3.x (0.4.0 feeds the encoder 4:2:0 itself). See docs/monologue.md.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <libavcodec/avcodec.h>
#include <libavutil/dict.h>
#include <libavutil/error.h>
#include <libavcodec/version_major.h>
#include <errno.h>
#define STR_(x) #x
#define STR(x) STR_(x)

static int is_target(void) {
  char comm[32] = {0}; FILE *f = fopen("/proc/self/comm", "r");
  if (!f) return 0;
  if (!fgets(comm, sizeof comm, f)) comm[0] = 0;
  fclose(f);
  return strncmp(comm, "monologue", 9) == 0;
}

int avcodec_open2(AVCodecContext *ctx, const AVCodec *codec, AVDictionary **opts) {
  static int (*real)(AVCodecContext *, const AVCodec *, AVDictionary **);
  if (!real) real = dlsym(RTLD_NEXT, "avcodec_open2");
  if (!real) {  // Qt dlopens its FFmpeg plugin after we load: look the symbol up there
    void *h = dlopen("libavcodec.so." STR(LIBAVCODEC_VERSION_MAJOR), RTLD_NOW | RTLD_NOLOAD);
    if (!h) h = dlopen("libavcodec.so." STR(LIBAVCODEC_VERSION_MAJOR), RTLD_NOW);
    if (h) real = dlsym(h, "avcodec_open2");
    if (!real) return AVERROR(ENOSYS);
  }
  const AVCodec *c = codec ? codec : (ctx ? ctx->codec : NULL);
  if (c && c->name && strcmp(c->name, "libx264") == 0 && is_target()) {
    const char *p = getenv("MONOLOGUE_X264_PRESET");
    AVDictionary *local = NULL, **o = opts ? opts : &local;
    av_dict_set(o, "preset", p && *p ? p : "veryfast", 0);
    int r = real(ctx, codec, o);
    av_dict_free(&local);
    return r;
  }
  return real(ctx, codec, opts);
}
