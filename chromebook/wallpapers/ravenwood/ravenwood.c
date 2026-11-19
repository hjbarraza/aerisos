/* ravenwood: a misty moonlit forest with one raven, for the terminal.
 *
 * The scene is painted as a greyscale picture at Braille-dot resolution (2 x 4 dots per cell)
 * and then every cell picks two greys and the glyph that best splits its eight dots: a block
 * octant where the picture is solid, a Braille pattern where it is stippled (leaves, fireflies).
 * Run it at a small font and the dots get small: at 5pt a dot is 2 x 2 screen pixels.
 *
 * Depth: four layers of trunks, a foreground tree with the raven's limb, and grass, each
 * answering the wind at its own pace (far trees slow, near ones quicker), with two sheets of
 * mist between them moving at their own speeds. The viewpoint never moves. Wind: far trees lean as a whole, the foreground
 * tree moves joint by joint, grass and leaves flutter. The raven looks about, calls, ruffles,
 * hops, and flies between perches.
 *
 *   ravenwood [--fps N] [--seed N] [--stats] [--bench FRAMES]
 * Build: cc -O2 -march=native -ffast-math -o ravenwood ravenwood.c -lm
 */
#define _GNU_SOURCE
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include "octant.h"

#define PI 3.14159265f
static uint32_t rng_s = 0x9e3779b9u;
static inline uint32_t rnd(void) { rng_s ^= rng_s << 13; rng_s ^= rng_s >> 17; rng_s ^= rng_s << 5; return rng_s; }
static inline float frand(void) { return (rnd() >> 8) * (1.0f / 16777216.0f); }
static inline float srand1(void) { return frand() * 2.0f - 1.0f; }
static inline float rrange(float a, float b) { return a + (b - a) * frand(); }
static inline float clampf(float v, float a, float b) { return v < a ? a : v > b ? b : v; }
static inline float smooth(float a, float b, float x) { x = clampf((x - a) / (b - a), 0, 1); return x * x * (3 - 2 * x); }
static inline uint32_t hash2(int x, int y) {
    uint32_t h = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return h ^ (h >> 16);
}
static float vnoise(float x, float y) {
    int xi = (int)floorf(x), yi = (int)floorf(y);
    float fx = x - xi, fy = y - yi;
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
    float a = (hash2(xi, yi) & 0xffff) / 65535.0f, b = (hash2(xi + 1, yi) & 0xffff) / 65535.0f;
    float c = (hash2(xi, yi + 1) & 0xffff) / 65535.0f, d = (hash2(xi + 1, yi + 1) & 0xffff) / 65535.0f;
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
}
static float fbm(float x, float y) {
    return 0.5f * vnoise(x, y) + 0.27f * vnoise(x * 2.03f + 7.1f, y * 2.03f + 3.3f)
         + 0.15f * vnoise(x * 4.1f + 1.7f, y * 4.1f + 9.2f) + 0.08f * vnoise(x * 8.3f, y * 8.3f + 4.4f);
}
static double now_s(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec * 1e-9; }

/* ---------- screen ---------- */
static int cols, rows, W, H;
static float asp = 1.0f, K = 1.0f;        /* dot width / height; scale against a 674-dot-wide picture */
static uint8_t *fb;                       /* the picture: grey per dot, bit 0 set = stippled */
static uint8_t *sky, *skycell;            /* backdrop per dot; its mean per cell */
static uint8_t *hm;                       /* foreground mask: 1 wood, 2 highlight, 3 leaf, 4 raven */
static int hx0, hx1, hy0, hy1;            /* its bounding box this frame */
static uint8_t *fogA[2], *fogC, *arow, *crow;
static uint32_t *pg; static uint8_t *pf, *pb;
static char *out;
static float moonx, moony, moonr;
static char num[1000][4]; static uint8_t numlen[1000];
static uint8_t BRAILLE[256];
static char statline[128];

/* the breeze at a place and time: 0 nearly still .. 1 a gust */
static inline float breeze(float t, float x) {
    float g = 0.50f + 0.30f * sinf(0.19f * t + x * 0.006f) + 0.20f * sinf(0.47f * t + x * 0.011f + 1.7f);
    return g * (0.62f + 0.38f * sinf(0.043f * t + 0.6f));
}

/* ---------- background layers: trees painted once, then leaned by the wind row by row ---------- */
typedef struct { int x0, w, ytop, ybase; uint8_t *pix; int16_t *ra, *rb; float phase, flex, om; } Tree;
typedef struct { Tree *t; int n; float par; int mul; int margin; } Layer;
#define NL 4
static Layer layer[NL];
static int layer_gy[NL];

static uint8_t *cv; static int cvw, cx0, cx1, cy0;
static inline void cset(int x, int y, int v) {
    if (x < 0 || x >= cvw || y < 0 || y >= H) return;
    cv[y * cvw + x] = (uint8_t)(v < 2 ? 2 : v > 254 ? 254 : v);
    if (x < cx0) cx0 = x; if (x > cx1) cx1 = x; if (y < cy0) cy0 = y;
}
static void cdisc(float x, float y, float r, int tone, int rim, int side) {
    int ir = (int)ceilf(r);
    for (int dy = -ir; dy <= ir; dy++)
        for (int dx = -ir; dx <= ir; dx++) {
            if (dx * dx + dy * dy > r * r + 0.3f) continue;
            float s = clampf(dx / (r + 0.5f) * side * 0.7f + 0.3f - dy / (r + 0.5f) * 0.3f, 0, 1);
            cset((int)lroundf(x) + dx, (int)lroundf(y) + dy, (tone + (int)(rim * s * s)) & ~1);
        }
}
static void cbranch(float x, float y, float ang, float len, float r, int depth, int tone, int rim, int side, float leafy) {
    int steps = (int)len + 1; float bend = srand1() * 0.4f / steps;
    for (int s = 0; s < steps; s++) {
        cdisc(x, y, r, tone, rim, side);
        x += sinf(ang); y -= cosf(ang) * asp; ang += bend; ang *= 0.988f; r = fmaxf(0.5f, r * 0.994f);
    }
    if (depth > 0) {
        int kids = 2 + (rnd() % 3 == 0);
        for (int k = 0; k < kids; k++)
            cbranch(x, y, ang + (k == 0 ? -1 : k == 1 ? 1 : 0.2f) * rrange(0.3f, 0.75f), len * rrange(0.5f, 0.75f),
                    fmaxf(0.5f, r * 0.65f), depth - 1, tone, rim, side, leafy);
    } else if (leafy > 0) {
        int n = (int)(leafy * (10 + len * 2.2f)); float R = 3.0f * K + len * 0.55f;
        for (int i = 0; i < n; i++) {
            float a = frand() * 6.2832f, d = R * sqrtf(frand());
            int lx = (int)(x + cosf(a) * d * 1.3f), ly = (int)(y + sinf(a) * d * 0.8f - R * 0.3f);
            if (lx >= 0 && lx < cvw && ly >= 0 && ly < H && !cv[ly * cvw + lx]) cset(lx, ly, ((tone > 8 ? tone - 6 : 2) & ~1) | 1);
        }
    }
}
static void crop(Tree *t, int xoff) {
    if (cx1 < cx0) { cx0 = 0; cx1 = 0; cy0 = H - 1; }
    t->w = cx1 - cx0 + 1; t->ytop = cy0; t->x0 = xoff + cx0;
    int hh = H - cy0;
    t->pix = malloc((size_t)t->w * hh); t->ra = malloc(hh * sizeof(int16_t)); t->rb = malloc(hh * sizeof(int16_t));
    for (int y = cy0; y < H; y++) {
        uint8_t *src = cv + y * cvw + cx0, *dst = t->pix + (size_t)(y - cy0) * t->w;
        memcpy(dst, src, t->w);
        int a = 0, b = t->w;
        while (a < b && !dst[a]) a++;
        while (b > a && !dst[b - 1]) b--;
        t->ra[y - cy0] = a; t->rb[y - cy0] = b;
    }
}
static void cclear(int w) { cvw = w; memset(cv, 0, (size_t)cvw * H); cx0 = cvw; cx1 = -1; cy0 = H; }

static void make_tree(Tree *t, int xc_layer, int ybase, float r0, int tone, int rim, int bark, int nb, int bdepth, float leafy, int side) {
    float maxlen = r0 * 11 + 10 * K;
    int w = (int)(2 * (maxlen * 2.2f + r0 * 3) + 24); if (w > 2 * W) w = 2 * W;
    cclear(w);
    float xb = w * 0.5f, lean = srand1() * 0.035f, wob = rrange(0.5f, 2.0f) * r0 * 0.5f, ph = frand() * 6.28f, seed = frand() * 100;
    for (int y = ybase + (int)(r0 * 0.6f); y >= 0; y--) {
        float up = (ybase - y) / asp;
        float xc = xb + lean * up + wob * sinf(up * 0.012f / K + ph);
        float r = r0 * (1.0f - 0.32f * up / H) + (up > 0 ? r0 * 0.7f * expf(-up / (r0 * 1.3f + 1)) : r0 * 0.7f);
        int a = (int)lroundf(xc - r), b = (int)lroundf(xc + r);
        for (int x = a; x <= b; x++) {
            float n = (x - xc) / (r + 0.5f) * side;
            float s = clampf(n * 0.75f + 0.25f, 0, 1);
            int v = tone + (int)(rim * s * s);
            if (bark) {
                v += (int)((vnoise(x * 0.55f / K + seed, y * 0.045f / K) - 0.5f) * bark);
                if (hash2(x + (int)seed, y / 3) % 9 == 0) v += bark / 3;
            }
            cset(x, y, v & ~1);
        }
    }
    for (int i = 0; i < nb; i++) {
        float up = rrange(0.18f, 0.95f) * ybase; int s = rnd() & 1 ? 1 : -1;
        float xc = xb + lean * up + wob * sinf(up * 0.012f / K + ph);
        float r = r0 * (1.0f - 0.32f * up / H);
        cbranch(xc + s * r * 0.8f, ybase - up * asp, s * rrange(0.55f, 1.3f), rrange(4, 9) * r0 + 4 * K, fmaxf(0.6f, r0 * 0.2f),
                bdepth, tone, rim, side, leafy);
    }
    crop(t, xc_layer - (int)xb);
    t->ybase = ybase; t->phase = frand() * 6.28f; t->om = rrange(0.7f, 1.3f);
}

static void make_ground(Tree *t, int lw, int gy, int tone, float bump, float fern) {
    cclear(lw);
    float seed = frand() * 100;
    for (int x = 0; x < lw; x++) {
        int top = gy - (int)(bump * (fbm(x * 0.012f / K + seed, 1.0f) - 0.4f) + 1.5f * K * vnoise(x * 0.3f / K, seed));
        for (int y = top; y < H; y++) cset(x, y, (tone - (y - top > 3 ? 4 : 0) + ((hash2(x, y) & 7) == 0 ? 4 : 0)) & ~1);
    }
    int nf = (int)(lw / (16 * K));                   /* ferns and saplings along the floor */
    for (int i = 0; i < nf; i++) {
        float x = frand() * lw, y = gy - bump * 0.2f;
        int blades = 3 + rnd() % 5;
        for (int b = 0; b < blades; b++) {
            float ang = srand1() * 1.1f, len = fern * rrange(0.5f, 1.4f), px = x, py = y;
            for (int s = 0; s < (int)len; s++) {
                cset((int)px, (int)py, tone & ~1);
                if (s > 2 && (s & 1)) { cset((int)(px + cosf(ang) * 1.5f), (int)(py + sinf(fabsf(ang)) * 1.5f), (tone & ~1) | 1);
                                        cset((int)(px - cosf(ang) * 1.5f), (int)(py - sinf(fabsf(ang)) * 1.5f), (tone & ~1) | 1); }
                px += sinf(ang); py -= cosf(ang) * asp; ang *= 1.06f;
            }
        }
    }
    crop(t, 0);
    t->ybase = H; t->flex = 0; t->phase = 0; t->om = 1;
}

static void layers_build(void) {
    static const struct { float par, spacing, r0, r1, flex, gy, bump, fern; int tone, rim, bark, mul, nb, bdepth; float leafy; } P[NL] = {
        /* far:  only darkens the mist behind it */
        { 0.10f, 13, 0.9f, 1.8f, 1.2f, 0.790f, 5, 3, 0, 0, 0, 190, 1, 0, 0 },
        { 0.24f, 30, 1.8f, 3.4f, 1.8f, 0.815f, 8, 5, 0, 0, 0, 120, 3, 1, 0 },
        /* middle and near: their own greys, lit on the moon's side */
        { 0.46f, 62, 4.0f, 7.0f, 2.4f, 0.860f, 10, 9, 26, 22, 10, 0, 5, 2, 1.0f },
        { 0.72f, 150, 9.0f, 15.0f, 2.2f, 0.915f, 9, 13, 8, 50, 16, 0, 2, 2, 0.6f },
    };
    free(cv); cv = malloc((size_t)(W * 3) * H);
    for (int l = 0; l < NL; l++) {
        Layer *L = &layer[l];
        for (int i = 0; i < L->n; i++) { free(L->t[i].pix); free(L->t[i].ra); free(L->t[i].rb); }
        free(L->t);
        L->par = P[l].par; L->mul = P[l].mul;
        L->margin = (int)(P[l].par * 34 * K) + 8;
        int lw = W + 2 * L->margin;
        int n = (int)(lw / (P[l].spacing * K)); if (n < 2) n = 2;
        L->t = calloc(n + 1, sizeof(Tree)); L->n = 0;
        int gy = (int)(P[l].gy * H);
        layer_gy[l] = gy;
        for (int i = 0; i < n; i++) {
            float x = (i + 0.5f + srand1() * 0.42f) * lw / n;
            float r0 = rrange(P[l].r0, P[l].r1) * K;
            int side = x - L->margin < moonx ? 1 : -1;
            int tone = P[l].mul ? 100 : P[l].tone + (int)(srand1() * 3);
            make_tree(&L->t[L->n], (int)x, gy, r0, tone, P[l].rim, P[l].bark, P[l].nb, P[l].bdepth, P[l].leafy, side);
            L->t[L->n].flex = P[l].flex * K * rrange(0.7f, 1.3f);
            L->n++;
        }
        make_ground(&L->t[L->n], lw, gy, P[l].mul ? 100 : P[l].tone, P[l].bump * K, P[l].fern * K);
        L->n++;
    }
}

static void layer_blit(const Layer *L, float cam, float t) {
    int lshift = (int)lroundf(-cam * L->par) - L->margin;
    for (int i = 0; i < L->n; i++) {
        const Tree *tr = &L->t[i];
        float A = tr->flex * breeze(t * (0.55f + 0.6f * L->par), tr->x0) * (1.0f + 0.55f * sinf(tr->om * (0.6f + 0.8f * L->par) * t + tr->phase));   /* leaning downwind, far trees slower */
        float inv = 1.0f / (tr->ybase + 1);
        for (int y = tr->ytop; y < H; y++) {
            int row = y - tr->ytop; int a = tr->ra[row], b = tr->rb[row];
            if (a >= b) continue;
            float u = (tr->ybase - y) * inv; if (u < 0) u = 0;
            int sx = tr->x0 + lshift + (int)lroundf(A * u * u);
            int d0 = sx + a, d1 = sx + b;
            const uint8_t *src = tr->pix + (size_t)row * tr->w + a;
            if (d0 < 0) { src -= d0; d0 = 0; }
            if (d1 > W) d1 = W;
            uint8_t *dst = fb + y * W + d0; int n = d1 - d0;
            if (n <= 0) continue;
            if (L->mul) { int m = L->mul; for (int k = 0; k < n; k++) if (src[k]) dst[k] = (uint8_t)((dst[k] * m) >> 8) & ~1; }
            else for (int k = 0; k < n; k++) dst[k] = src[k] ? src[k] : dst[k];
        }
    }
}

/* ---------- backdrop and mist ---------- */
static void sky_build(void) {
    moonx = W * 0.63f; moony = H * 0.27f; moonr = H * 0.058f;
    for (int y = 0; y < H; y++) {
        float yf = (float)y / H;
        for (int x = 0; x < W; x++) {
            float dx = x - moonx, dy = (y - moony) / asp, d2 = dx * dx + dy * dy;
            float bell = expf(-(yf - 0.58f) * (yf - 0.58f) / 0.075f);
            float v = 16 + 40 * bell + 120 * expf(-d2 / (W * W * 0.045f)) + 70 * expf(-d2 / (W * W * 0.0035f));
            int stip = 0;
            float cn = fbm(x * 0.022f / K, y * 0.03f / K + 5);
            float edge = 0.22f + 0.36f * (cn - 0.45f);          /* the canopy overhead */
            if (d2 < moonr * moonr) v = 238;
            if (yf < edge) {
                float hole = fbm(x * 0.09f / K + 9, y * 0.09f / K);
                if (hole > 0.60f && yf > edge - 0.16f) { v *= 0.85f; }
                else { v = 3 + v * 0.10f; if (yf > edge - 0.035f && (hash2(x, y) & 3) == 0) { v = 60 + v; stip = 1; } }
            } else if (yf < edge + 0.02f && (hash2(x, y) & 3) == 0) { v = 5; stip = 1; }
            if (yf > 0.78f) v *= 1.0f - 0.75f * smooth(0.78f, 0.93f, yf);
            sky[y * W + x] = ((uint8_t)clampf(v, 0, 254) & ~1) | stip;
        }
    }
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++) {
            int s = 0;
            for (int yy = 0; yy < 4; yy++) s += sky[(r * 4 + yy) * W + c * 2] + sky[(r * 4 + yy) * W + c * 2 + 1];
            skycell[r * cols + c] = s >> 3;
        }
}

static void fog_update(int k, float t) {
    for (int r = 0; r < rows; r++) {
        float yf = (r + 0.5f) / rows, v = yf * 92;
        for (int c = 0; c < cols; c++) {
            float u = (float)c / cols * 337, a;
            if (k == 0) {
                float n = fbm(u * 0.018f + t * 0.011f, v * 0.055f - t * 0.002f);
                float band = smooth(0.12f, 0.55f, yf) * (1.0f - 0.45f * smooth(0.82f, 1.0f, yf));
                float shaft = 0.72f + 0.56f * vnoise((u - (moonx / W * 337) + (v - 25) * 0.9f) * 0.055f + t * 0.006f, 1.0f);
                a = (0.10f + 0.72f * smooth(0.28f, 0.78f, n)) * band * shaft;
                fogC[r * cols + c] = (uint8_t)clampf(40 + 0.62f * skycell[r * cols + c], 0, 230);
                if (a > 0.85f) a = 0.85f;
            } else {
                float n = fbm(u * 0.03f + t * 0.027f + 50, v * 0.085f + 7 + t * 0.003f);
                a = 0.62f * smooth(0.38f, 0.80f, n) * smooth(0.30f, 0.80f, yf);
            }
            fogA[k][r * cols + c] = (uint8_t)(a * 255);
        }
    }
}
static void fog_apply(int k, float strength) {
    for (int r = 0; r < rows; r++) {
        const uint8_t *A = fogA[k] + r * cols, *C = fogC + r * cols;
        int s = (int)(strength * 256);
        for (int c = 0; c < cols; c++) { arow[2 * c] = arow[2 * c + 1] = (uint8_t)((A[c] * s) >> 8); crow[2 * c] = crow[2 * c + 1] = C[c]; }
        for (int yy = 0; yy < 4; yy++) {
            uint8_t *p = fb + (r * 4 + yy) * W;
            for (int x = 0; x < W; x++) {
                int v = p[x];
                p[x] = (uint8_t)(((v * (256 - arow[x]) + crow[x] * arow[x]) >> 8) & ~1) | (v & 1);
            }
        }
    }
}

/* ---------- foreground mask drawing ---------- */
static inline void hset(int x, int y, uint8_t v) {
    if (x < 0 || x >= W || y < 0 || y >= H) return;
    hm[y * W + x] = v;
    if (x < hx0) hx0 = x; if (x > hx1) hx1 = x; if (y < hy0) hy0 = y; if (y > hy1) hy1 = y;
}
static void hdisc(float x, float y, float r, uint8_t v) {
    if (r < 0.75f) { hset((int)lroundf(x), (int)lroundf(y), v); return; }
    int ir = (int)ceilf(r), xi = (int)lroundf(x), yi = (int)lroundf(y);
    for (int dy = -ir; dy <= ir; dy++) {
        float h2 = r * r - dy * dy / (asp * asp); if (h2 < 0) continue;
        int h = (int)(sqrtf(h2) + 0.35f), yy = yi + dy;
        if (yy < 0 || yy >= H) continue;
        int a = xi - h, b = xi + h; if (a < 0) a = 0; if (b >= W) b = W - 1;
        if (a > b) continue;
        memset(hm + yy * W + a, v, b - a + 1);
        if (a < hx0) hx0 = a; if (b > hx1) hx1 = b; if (yy < hy0) hy0 = yy; if (yy > hy1) hy1 = yy;
    }
}
static void hseg(float x0, float y0, float x1, float y1, float r0, float r1, uint8_t v) {
    float d = hypotf(x1 - x0, y1 - y0); int n = (int)(d * 1.3f) + 1;
    for (int i = 0; i <= n; i++) { float f = (float)i / n; hdisc(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, r0 + (r1 - r0) * f, v); }
}
static void hpoly(const float *p, int n, uint8_t v) {
    float ymin = 1e9f, ymax = -1e9f;
    for (int i = 0; i < n; i++) { if (p[2 * i + 1] < ymin) ymin = p[2 * i + 1]; if (p[2 * i + 1] > ymax) ymax = p[2 * i + 1]; }
    int y0 = (int)floorf(ymin), y1 = (int)ceilf(ymax); if (y0 < 0) y0 = 0; if (y1 >= H) y1 = H - 1;
    for (int y = y0; y <= y1; y++) {
        float yc = y + 0.5f, xs[24]; int k = 0;
        for (int i = 0; i < n && k < 24; i++) {
            float ax = p[2 * i], ay = p[2 * i + 1], bx = p[2 * ((i + 1) % n)], by = p[2 * ((i + 1) % n) + 1];
            if ((ay <= yc && by > yc) || (by <= yc && ay > yc)) xs[k++] = ax + (yc - ay) / (by - ay) * (bx - ax);
        }
        for (int i = 1; i < k; i++) { float q = xs[i]; int j = i - 1; while (j >= 0 && xs[j] > q) { xs[j + 1] = xs[j]; j--; } xs[j + 1] = q; }
        for (int i = 0; i + 1 < k; i += 2) {
            int a = (int)lroundf(xs[i]), b = (int)lroundf(xs[i + 1]) - 1; if (b < a) b = a;
            for (int x = a; x <= b; x++) hset(x, y, v);
        }
    }
}
static void hellipse(float cx, float cy, float rx, float ry, float ux, float uy, uint8_t v) {
    float R = fmaxf(rx, ry); int x0 = (int)(cx - R - 1), x1 = (int)(cx + R + 1), y0 = (int)(cy - R * asp - 1), y1 = (int)(cy + R * asp + 1);
    for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++) {
            float dx = x + 0.5f - cx, dy = (y + 0.5f - cy) / asp;
            float a = (dx * ux + dy * uy) / rx, b = (-dx * uy + dy * ux) / ry;
            if (a * a + b * b <= 1.0f) hset(x, y, v);
        }
}

/* ---------- the foreground tree: a hierarchy of branches, so the wind moves it joint by joint ---------- */
typedef struct { int parent, level, steps; float rel, len, r0, r1, bend, phase, rootx, rooty; } Branch;
typedef struct { int br; float ox, oy, ph; } Leaf;
#define MAXBR 900
#define MAXLEAF 9000
static Branch br[MAXBR]; static float bex[MAXBR], bey[MAXBR], bea[MAXBR]; static int nbr;
static Leaf leaf[MAXLEAF]; static int nleaf;
#define NPERCH 3                                   /* the raven's own perches; a fourth is where a guest lands */
static int perch_br[4]; static float perch_fr[4], perchx[4], perchy[4], perch_off;
static float stumpx, stumpw, stumph; static int perch_sel;

static int hb_add(int parent, float rel, float len, float r0, float r1, int level) {
    if (nbr >= MAXBR) return nbr - 1;
    Branch *b = &br[nbr];
    b->parent = parent; b->rel = rel; b->len = len; b->r0 = r0; b->r1 = r1; b->level = level;
    b->steps = (int)len + 1; b->bend = srand1() * 0.22f / b->steps; b->phase = frand() * 6.2832f;
    return nbr++;
}
static void hb_leaves(int id, int n, float R) {
    for (int i = 0; i < n && nleaf < MAXLEAF; i++) {
        float a = frand() * 6.2832f, d = R * sqrtf(frand());
        leaf[nleaf++] = (Leaf){ id, cosf(a) * d * 1.25f, sinf(a) * d * 0.8f + R * 0.25f, frand() * 6.28f };
    }
}
static void hb_twigs(int id, int depth, float len, float r, float leafR) {
    int level = br[id].level + 1;
    int kids = 2 + (rnd() % 3 == 0);
    for (int k = 0; k < kids; k++) {
        float rel = (k == 0 ? -1 : k == 1 ? 1 : 0.15f) * rrange(0.3f, 0.8f);
        float l = len * rrange(0.6f, 0.85f);
        int c = hb_add(id, rel, l, r, fmaxf(0.4f, r * 0.6f), level);
        if (depth > 0) hb_twigs(c, depth - 1, l, fmaxf(0.4f, r * 0.6f), leafR);
        else hb_leaves(c, 16 + rnd() % 14, leafR);
        if (depth == 1) hb_leaves(c, 8, leafR * 0.8f);
    }
}
static void hero_build(void) {
    uint32_t keep = rng_s; rng_s = 0x7a11e5u;
    nbr = 0; nleaf = 0;
    float w = W, h = H / asp;
    /* the left tree and the long limb the raven likes */
    int t0 = hb_add(-1, 0.05f, 0.50f * h, 0.031f * w, 0.025f * w, 0); br[t0].rootx = 0.105f * w; br[t0].rooty = H + 6;
    int t1 = hb_add(t0, -0.03f, 0.66f * h, 0.025f * w, 0.019f * w, 0);
    int la = hb_add(t0, 1.47f, 0.15f * w, 0.012f * w, 0.0085f * w, 1);
    int lb = hb_add(la, 0.07f, 0.13f * w, 0.0085f * w, 0.0055f * w, 2);
    int lc = hb_add(lb, -0.12f, 0.10f * w, 0.0055f * w, 0.0025f * w, 3);
    br[t0].bend = 0; br[t1].bend = 0.0002f / K;
    br[la].bend = -0.0006f / K; br[lb].bend = 0.0010f / K; br[lc].bend = 0.0005f / K;   /* a level limb, sagging a little at the end */
    int ua = hb_add(la, -1.15f, 0.085f * w, 0.006f * w, 0.003f * w, 2); hb_twigs(ua, 2, 0.055f * w, 0.0025f * w, 0.016f * w);
    int ub = hb_add(lb, 0.75f, 0.05f * w, 0.004f * w, 0.002f * w, 3); hb_twigs(ub, 1, 0.04f * w, 0.0018f * w, 0.014f * w);
    hb_twigs(lc, 2, 0.05f * w, 0.002f * w, 0.015f * w);
    int hi = hb_add(t1, 1.05f, 0.20f * w, 0.010f * w, 0.005f * w, 1);     /* a high limb whose twigs hang into view */
    int hd = hb_add(hi, 0.75f, 0.07f * w, 0.004f * w, 0.002f * w, 2); hb_twigs(hd, 2, 0.05f * w, 0.002f * w, 0.017f * w);
    int he = hb_add(hi, 0.10f, 0.10f * w, 0.005f * w, 0.0025f * w, 2); hb_twigs(he, 2, 0.055f * w, 0.002f * w, 0.017f * w);
    int lf = hb_add(t0, -0.85f, 0.10f * w, 0.008f * w, 0.004f * w, 1); hb_twigs(lf, 1, 0.05f * w, 0.003f * w, 0.016f * w);
    perch_br[0] = lb; perch_fr[0] = 0.62f;
    perch_br[3] = la; perch_fr[3] = 0.74f;
    /* the right tree, with a broken stub */
    int r0 = hb_add(-1, -0.04f, 0.66f * h, 0.017f * w, 0.014f * w, 0); br[r0].rootx = 0.925f * w; br[r0].rooty = H + 6;
    int r1 = hb_add(r0, 0.03f, 0.5f * h, 0.014f * w, 0.011f * w, 0);
    int st = hb_add(r0, -1.18f, 0.085f * w, 0.0065f * w, 0.0045f * w, 1);
    int su = hb_add(st, 0.9f, 0.04f * w, 0.003f * w, 0.0015f * w, 2); hb_twigs(su, 1, 0.035f * w, 0.0015f * w, 0.013f * w);
    int rh = hb_add(r1, -0.9f, 0.12f * w, 0.006f * w, 0.003f * w, 1); hb_twigs(rh, 2, 0.05f * w, 0.002f * w, 0.016f * w);
    perch_br[1] = st; perch_fr[1] = 0.78f;
    perch_br[2] = -1;
    stumpx = 0.585f * w; stumpw = 0.022f * w; stumph = 0.085f * H;
    rng_s = keep;
}

static void hero_draw(float t, float cam) {
    int shift = (int)lroundf(-cam);
    /* the near ground and a stump */
    for (int x = 0; x < W; x++) {
        int wx = x - shift;
        int top = (int)(H * 0.965f - 5 * K * fbm(wx * 0.01f / K, 2.0f) - 1.5f * K * vnoise(wx * 0.4f / K, 7.0f));
        for (int y = top; y < H; y++) hm[y * W + x] = 5;
        if (top < hy0) hy0 = top;
    }
    hx0 = 0; hx1 = W - 1; hy1 = H - 1;
    {
        float sx = stumpx + shift, by = H * 0.97f, ty = by - stumph;
        float p[] = { sx - stumpw * 1.5f, by, sx - stumpw, by - stumph * 0.45f, sx - stumpw * 0.95f, ty + 2 * K, sx - stumpw * 0.5f, ty - 2 * K,
                      sx - stumpw * 0.1f, ty + 1.5f * K, sx + stumpw * 0.45f, ty - 1 * K, sx + stumpw * 0.9f, ty + 3 * K, sx + stumpw * 1.05f, by - stumph * 0.4f,
                      sx + stumpw * 1.7f, by };
        hpoly(p, 9, 1);
        perchx[2] = sx - stumpw * 0.5f; perchy[2] = ty - 2 * K;
    }
    for (int i = 0; i < nbr; i++) {
        Branch *b = &br[i];
        float x, y, ang;
        if (b->parent < 0) { x = b->rootx + shift; y = b->rooty; ang = b->rel; }
        else { x = bex[b->parent]; y = bey[b->parent]; ang = bea[b->parent] + b->rel; }
        if (b->level > 0) {
            float g = breeze(t, x), L = b->level;
            ang += g * 0.006f * L + g * (0.006f + 0.005f * L) * sinf((1.2f + 0.5f * L) * t + b->phase);
            if (b->level >= 3) ang += g * 0.02f * sinf((5.0f + L) * t + b->phase * 5.0f);
        }
        for (int s = 0; s < b->steps; s++) {
            float r = b->r0 + (b->r1 - b->r0) * s / b->steps;
            hdisc(x, y, r, 1);
            for (int k = 0; k < 4; k++)
                if (perch_br[k] == i && s == (int)(clampf(perch_fr[k] + (k == perch_sel ? perch_off : 0), 0.02f, 0.98f) * b->steps)) { perchx[k] = x; perchy[k] = y - r * asp; }
            x += sinf(ang); y -= cosf(ang) * asp; ang += b->bend;
        }
        bex[i] = x; bey[i] = y; bea[i] = ang;
    }
    for (int i = 0; i < nleaf; i++) {
        Leaf *l = &leaf[i];
        float g = breeze(t, bex[l->br]);
        int x = (int)lroundf(bex[l->br] + l->ox + g * 1.6f * K * sinf(3.1f * t + l->ph));
        int y = (int)lroundf(bey[l->br] + l->oy * asp + g * 0.8f * K * sinf(4.3f * t + l->ph * 2));
        if (x >= 0 && x < W && y >= 0 && y < H && !hm[y * W + x]) hset(x, y, 3);
    }
}

static void grass_draw(float t, float cam) {
    int shift = (int)lroundf(-cam * 1.35f);
    int span = W + (int)(100 * K), n = (int)(span / (2.2f * K));
    for (int i = 0; i < n; i++) {
        uint32_t h = hash2(i, 77);
        float x = (i * 2.2f * K) - 50 * K + shift + (h & 7) * 0.3f * K, y = H - 1;
        float len = (4 + (h >> 3 & 15) + ((h >> 7 & 31) == 0 ? 22 : 0)) * K * (0.8f + 0.5f * vnoise(i * 0.05f, 3));
        float g = breeze(t, x);
        float ang = ((int)(h >> 12 & 255) - 128) / 128.0f * 0.35f + g * 0.25f + g * 0.22f * sinf(2.6f * t + (h >> 20) * 0.01f + x * 0.05f);
        float curl = ang * 0.045f / K;
        for (int s = 0; s < (int)len; s++) {
            hset((int)lroundf(x), (int)lroundf(y), 5);
            if (len > 20 * K && s < 3) hset((int)lroundf(x) + 1, (int)lroundf(y), 5);
            x += sinf(ang); y -= cosf(ang) * asp; ang += curl;
        }
        if (len > 24 * K) { hset((int)x + 1, (int)y, 3); hset((int)x - 1, (int)y + 1, 3); hset((int)x, (int)y - 1, 3); hset((int)x + 1, (int)y + 2, 3); }
    }
}

/* ---------- the ravens ---------- */
enum { PERCH, FLY, AWAY, GROUND };
enum { A_NONE, A_CALL, A_RUFFLE, A_HOP, A_PREEN, A_CHEST, A_SCRATCH, A_WIPE, A_STRETCH, A_WINGSUP, A_TAILFAN, A_SIDESTEP,
       A_SETTLE, A_ONELEG, A_SLEEP, A_TILT, A_FIREFLY, A_STARE, A_STARTLE, A_SHAKE, A_HANG, A_STASH,
       A_BOW, A_BILL, A_ALLO, A_ALLOED, A_PECK, A_WALK, NACT };
static const char *ACTNAME[NACT] = { "none", "call", "ruffle", "hop", "preen", "chest", "scratch", "wipe", "stretch", "wingsup", "tailfan",
    "sidestep", "settle", "oneleg", "sleep", "tilt", "firefly", "stare", "startle", "shake", "hang", "stash", "bow", "bill", "allo", "alloed", "peck", "walk" };
static const float ACTDUR[NACT] = { 0, 2.4f, 1.1f, 0.34f, 3.6f, 2.6f, 1.8f, 2.2f, 2.8f, 2.0f, 1.4f, 1.2f, 12, 14, 55, 2.5f, 5, 2.5f, 0.9f, 1.0f, 3.6f, 1.6f,
    2.2f, 2.6f, 3.2f, 3.2f, 1.1f, 0 };
/* the pose: everything the drawing needs beyond where the head points */
enum { P_LEAN, P_OPEN, P_PUFF, P_CROUCH, P_HFWD, P_HDX, P_HDY, P_WINGL, P_WINGUP, P_FAN, P_LEGUP, P_ONELEG, P_ROT, P_EYE, P_TUCK, NP };
static const float PDEF[NP]  = { 0.70f, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
static const float PRATE[NP] = { 7, 22, 14, 7, 7, 9, 9, 6, 9, 8, 10, 5, 5, 14, 6 };
typedef struct {
    int state, perch, to, d, act, step, flipped, blink, carry, present, paired, rollit, steps;
    float x, y, S, t, dur, look, next, actt, adur, away, flap, pitch, rollf, pfo, gx, gxT, walkph, sdir;
    float yaw, yawT, tilt, tiltT, p[NP];
    float p0x, p0y, c1x, c1y, c2x, c2y, endx, endy;
} Raven;
static Raven rav[2]; static Raven *cr = &rav[0];
#define rv (*cr)
static int testact, testguest;      /* for trying things out */
#define NFLY 14
static float ffx[NFLY], ffy[NFLY], ffb[NFLY];
static int vis_on; static float vis_x, vis_y;

static float r_ox, r_oy, r_c, r_s, r_my = 1; static int r_d;
static inline void rp(float x, float y, float *o) {          /* raven units (x forward, y up) -> dots */
    y *= r_my;
    float xr = x * r_c - y * r_s, yr = x * r_s + y * r_c;
    o[0] = r_ox + r_d * xr * rv.S; o[1] = r_oy - yr * rv.S * asp;
}
static void rpoly(const float *loc, int n, uint8_t v) { float p[40]; for (int i = 0; i < n; i++) rp(loc[2 * i], loc[2 * i + 1], p + 2 * i); hpoly(p, n, v); }
static void rseg(float x0, float y0, float x1, float y1, float ra, float rb, uint8_t v) {
    float a[2], b[2]; rp(x0, y0, a); rp(x1, y1, b); hseg(a[0], a[1], b[0], b[1], ra * rv.S, rb * rv.S, v);
}
static void rell(float cx, float cy, float rx, float ry, float ang, uint8_t v) {
    float c[2], e[2]; rp(cx, cy, c); rp(cx + cosf(ang), cy + sinf(ang), e);
    float ux = e[0] - c[0], uy = (e[1] - c[1]) / asp, l = hypotf(ux, uy) + 1e-6f;
    hellipse(c[0], c[1], rx * rv.S, ry * rv.S, ux / l, uy / l, v);
}
static void beak(float hx, float hy, float yaw, float tilt, float open) {
    float cu = cosf(tilt), su = sinf(tilt), ox = hx + 0.10f * yaw, oy = hy - 0.01f;
    static const float up[] = { 0, 0.125f, 0.22f, 0.12f, 0.40f, 0.075f, 0.53f, 0.0f, 0.515f, -0.05f, 0.30f, -0.012f, 0, -0.012f };
    static const float lo[] = { 0, -0.012f, 0.43f, -0.022f, 0.30f, -0.08f, 0, -0.105f };
    float p[16];
    for (int i = 0; i < 7; i++) { float u = up[2 * i] * yaw, v = up[2 * i + 1]; p[2 * i] = ox + u * cu - v * su; p[2 * i + 1] = oy + u * su + v * cu; }
    rpoly(p, 7, 4);
    float co = cosf(-open), so = sinf(-open);
    for (int i = 0; i < 4; i++) {
        float u0 = lo[2 * i], v0 = lo[2 * i + 1] + 0.012f, u1 = (u0 * co - v0 * so) * yaw, v1 = u0 * so + v0 * co - 0.012f;
        p[2 * i] = ox + u1 * cu - v1 * su; p[2 * i + 1] = oy + u1 * su + v1 * cu;
    }
    rpoly(p, 4, 4);
    if (rv.carry) {                                           /* something held in the bill */
        float tx = ox + 0.47f * yaw * cu, ty = oy + 0.47f * yaw * su - 0.02f;
        if (rv.carry == 1) rseg(tx - 0.03f, ty - 0.20f, tx + 0.04f, ty + 0.22f, 0.02f, 0.015f, 4);
        else { float e[2]; rp(tx, ty, e); hset((int)lroundf(e[0]), (int)lroundf(e[1]), 6); hset((int)lroundf(e[0]) + 1, (int)lroundf(e[1]), 6); }
    }
}
static void wing(float phi, float scale, float sx, float sy, float sweep) {
    static const float w[] = { 0, .30f, .45f, .34f, .95f, .27f, 1.30f, .17f, 1.44f, .06f, 1.28f, .02f, 1.39f, -.06f, 1.22f, -.09f,
                               1.30f, -.17f, 1.12f, -.19f, 1.15f, -.27f, .9f, -.26f, .45f, -.30f, 0, -.26f };
    float sp = sinf(phi), cp = cosf(phi), p[28];
    for (int i = 0; i < 14; i++) {
        float s = w[2 * i] * scale, c = w[2 * i + 1] * (0.55f + 0.45f * fminf(1, scale));
        p[2 * i] = sx + c * 0.95f - 0.16f * s * cp - 0.10f * s * s * sp - sweep * s;        /* tips trail a little */
        p[2 * i + 1] = sy + s * sp + c * 0.16f * fabsf(cp) + 0.03f;
    }
    rpoly(p, 14, 4);
}

static void raven_perched(float t) {
    const float *p = rv.p;
    r_ox = rv.x; r_oy = rv.y + (1 - cosf(p[P_ROT])) * 4.5f * K; r_d = rv.d; r_c = cosf(-p[P_ROT]); r_s = sinf(-p[P_ROT]); r_my = 1;
    float th = p[P_LEAN], ca = cosf(th), sa = sinf(th), puff = p[P_PUFF] * (1.0f + 0.012f * sinf(1.7f * t + cr->S));
    float bx = -0.06f, by = 0.60f - 0.10f * p[P_CROUCH];
    float hx = bx + 0.52f * ca + 0.07f + p[P_HFWD] + p[P_HDX], hy = by + 0.52f * sa + 0.19f - 0.05f * p[P_CROUCH] + p[P_HDY];
    float wk = rv.state == GROUND && rv.act == A_WALK ? sinf(rv.walkph) : 0;
    /* legs and feet */
    if (p[P_LEGUP] > 0.05f) {                              /* one foot up to scratch the head */
        float u = p[P_LEGUP], j = 0.03f * sinf(t * 34);
        rseg(0.06f, by - 0.22f, 0.07f + (hx - 0.12f - 0.07f) * u, 0.02f + (hy - 0.20f + j - 0.02f) * u, 0.035f, 0.028f, 4);
    } else {
        rseg(0.06f, by - 0.22f, 0.07f + 0.10f * wk, 0.02f + 0.05f * fmaxf(0, wk), 0.035f, 0.028f, 4);
        rseg(-0.02f + 0.10f * wk, 0.015f + 0.05f * fmaxf(0, wk), 0.17f + 0.10f * wk, 0.0f + 0.05f * fmaxf(0, wk), 0.028f, 0.02f, 4);
    }
    if (p[P_ONELEG] < 0.5f) {
        rseg(-0.10f, by - 0.22f, -0.08f - 0.10f * wk, 0.02f + 0.05f * fmaxf(0, -wk), 0.035f, 0.028f, 4);
        rseg(-0.16f - 0.10f * wk, 0.015f + 0.05f * fmaxf(0, -wk), 0.0f - 0.10f * wk, 0.0f + 0.05f * fmaxf(0, -wk), 0.028f, 0.02f, 4);
    }
    rell(-0.02f, by - 0.22f, 0.17f, 0.13f, -0.3f, 4);
    /* tail: a long wedge behind and below, spread when fanned */
    float fan = p[P_FAN], tx = bx - 0.46f * ca, ty = by - 0.46f * sa;
    float ta = th + 0.26f + 0.05f * sinf(0.9f * t) * p[P_PUFF] + fan * 0.10f * sinf(t * 21), tc = -cosf(ta), ts = -sinf(ta), tw = 0.10f + 0.17f * fan;
    float tl[] = { tx - ts * 0.13f, ty + tc * 0.13f, tx + tc * 0.86f - ts * tw, ty + ts * 0.86f + tc * tw, tx + tc * 0.93f, ty + ts * 0.93f,
                   tx + tc * 0.84f + ts * (tw + 0.01f), ty + ts * 0.84f - tc * (tw + 0.01f), tx + ts * 0.12f, ty - tc * 0.12f };
    rpoly(tl, 5, 4);
    float wu = p[P_WINGUP], wl = p[P_WINGL];
    if (wu > 0.03f) wing(1.30f + 0.12f * sinf(t * 17), 0.95f * wu, bx + 0.14f * ca, by + 0.20f, 0.30f);        /* far wing, raised */
    rell(bx, by, 0.60f, 0.335f * puff, th, 4);                          /* body */
    /* folded wing: primaries reach back over the tail, a sheen along its upper edge */
    float wp[] = { bx + 0.20f * ca - 0.20f * sa, by + 0.20f * sa + 0.20f * ca, bx - 0.45f * ca - 0.20f * sa, by - 0.45f * sa + 0.20f * ca,
                   tx + tc * 0.52f - ts * 0.10f, ty + ts * 0.52f + tc * 0.10f, bx - 0.30f * ca + 0.12f * sa, by - 0.30f * sa - 0.12f * ca };
    rpoly(wp, 4, 4);
    if (wl < 0.2f && wu < 0.2f)
        rseg(bx + 0.18f * ca - 0.07f * sa, by + 0.18f * sa + 0.07f * ca, tx + tc * 0.30f - ts * 0.02f, ty + ts * 0.30f + tc * 0.02f, 0.012f, 0.012f, 2);
    if (wl > 0.03f) wing(-1.15f, 1.0f * wl, bx + 0.02f, by + 0.02f, 0.55f);                                      /* one wing stretched down and back */
    if (wu > 0.03f) wing(1.08f + 0.12f * sinf(t * 17 + 1), 1.05f * wu, bx + 0.05f * ca, by + 0.18f, 0.22f);     /* near wing, raised */
    /* neck, shaggy throat, head */
    rseg(bx + 0.30f * ca, by + 0.30f * sa, hx, hy, 0.27f * puff, 0.20f, 4);
    if (p[P_TUCK] < 0.5f)
        for (int k = 0; k < 3; k++) {
            float f = 0.25f + 0.28f * k, nx = bx + 0.30f * ca + (hx - bx - 0.30f * ca) * f + 0.17f, ny = by + 0.30f * sa + (hy - by - 0.30f * sa) * f - 0.10f;
            float hk = 0.085f + 0.3f * (p[P_PUFF] - 1);
            float hp[] = { nx - 0.07f, ny + 0.10f, nx + hk + 0.04f, ny - hk * 0.9f, nx - 0.10f, ny - 0.06f };
            rpoly(hp, 3, 4);
        }
    rell(hx, hy, 0.205f, 0.19f, 0, 4);
    int eyes = !rv.blink && p[P_EYE] < 0.5f;
    if (fabsf(rv.yaw) < 0.22f) {                           /* facing us: both eyes, the bill end-on */
        float bk[] = { hx - 0.06f, hy - 0.02f, hx + 0.06f, hy - 0.02f, hx, hy - 0.24f };
        rpoly(bk, 3, 4);
        if (eyes) for (int s = -1; s <= 1; s += 2) { float e[2]; rp(hx + s * 0.085f, hy + 0.045f, e); hset((int)lroundf(e[0]), (int)lroundf(e[1]), 6); }
    } else {
        if (p[P_TUCK] < 0.5f) beak(hx, hy, rv.yaw, rv.tilt, p[P_OPEN]);
        if (eyes) { float e[2]; rp(hx + 0.085f * rv.yaw, hy + 0.045f, e); hset((int)lroundf(e[0]), (int)lroundf(e[1]), 6); }
    }
}

static void raven_flying(void) {
    r_ox = rv.x; r_oy = rv.y; r_d = rv.d; r_c = cosf(rv.pitch); r_s = sinf(rv.pitch); r_my = rv.rollf;
    float phi = rv.flap;
    wing(phi + 0.22f, 1.08f, 0.16f, 0.06f, 0);                             /* far wing */
    float tl[] = { -0.45f, 0.10f, -1.12f, 0.13f, -1.22f, 0.0f, -1.10f, -0.13f, -0.45f, -0.10f };
    rpoly(tl, 5, 4);
    rell(0, 0, 0.62f, 0.235f, 0, 4);
    rseg(0.35f, 0.02f, 0.63f, 0.07f, 0.20f, 0.175f, 4);
    rell(0.64f, 0.075f, 0.185f, 0.17f, 0, 4);
    beak(0.64f, 0.075f, 1.0f, -0.08f, 0);
    { float e[2]; rp(0.72f, 0.115f, e); hset((int)lroundf(e[0]), (int)lroundf(e[1]), 6); }
    rseg(-0.25f, -0.20f, -0.50f, -0.17f, 0.04f, 0.03f, 4);                 /* feet tucked back */
    wing(phi, 1.22f, 0.10f, 0.05f, 0);                                     /* near wing */
    r_my = 1;
}

static float ground_top(float x) { return floorf(H * 0.965f - 5 * K * fbm(x * 0.01f / K, 2.0f) - 1.5f * K * vnoise(x * 0.4f / K, 7.0f)); }
static void perch_point(int k, float *x, float *y) {
    if (k >= 0) { *x = perchx[k]; *y = perchy[k]; }
    else { *x = rv.endx; *y = rv.endy; }
}
/* to: a perch, -1 out of the picture, -2 down to the ground */
static void raven_fly_to(int to) {
    rv.state = FLY; rv.to = to; rv.t = 0; rv.p0x = rv.x; rv.p0y = rv.y - 0.5f * rv.S; rv.act = A_NONE; rv.pfo = 0; rv.rollit = 0;
    if (to == -1) { rv.endx = frand() < 0.5f ? -4 * rv.S : W + 4 * rv.S; rv.endy = H * rrange(0.05f, 0.35f); }
    if (to == -2) { rv.gx = rv.endx = W * rrange(0.28f, 0.80f); rv.endy = ground_top(rv.endx) + 0.45f * rv.S; }
    float ex, ey; perch_point(to, &ex, &ey);
    float dx = ex - rv.p0x, dist = hypotf(dx, ey - rv.p0y);
    rv.c1x = rv.p0x + dx * 0.25f; rv.c1y = rv.p0y - rrange(0.03f, 0.14f) * H;
    rv.c2x = ex - dx * 0.25f;     rv.c2y = ey - rrange(0.10f, 0.22f) * H;
    rv.dur = fmaxf(1.5f, dist / (95.0f * K)); rv.d = dx >= 0 ? 1 : -1;
    if (rv.dur > 2.4f && to != -2 && (rnd() % 8) == 0) rv.rollit = 1;      /* now and then, a roll for the fun of it */
}
static void act_start(int a) {
    rv.act = a; rv.actt = 0; rv.flipped = 0; rv.step = 0; rv.adur = ACTDUR[a];
    if (a == A_SETTLE || a == A_ONELEG) rv.adur *= rrange(0.7f, 1.4f);
    if (a == A_SLEEP) rv.adur = rrange(40, 90);
    if (a == A_SIDESTEP) { rv.sdir = frand() < 0.5f ? -1 : 1; if (rv.pfo > 0.12f) rv.sdir = -1; if (rv.pfo < -0.2f) rv.sdir = 1; }
    if (a == A_TILT) rv.sdir = frand() < 0.5f ? -1 : 1;
}
/* turn the head toward a point in the picture */
static void look_at(float tx, float ty) {
    float hx = rv.x + rv.d * 0.4f * rv.S, hy = rv.y - 1.1f * rv.S * asp;
    float dx = (tx - hx) * rv.d, dy = hy - ty;
    rv.yawT = dx >= 0 ? 1.0f : -0.85f;
    rv.tiltT = clampf(atan2f(dy, fabsf(dx) + 1), -0.6f, 0.7f) * (dx >= 0 ? 1 : -1);
}
static int near_firefly(void) {
    int best = -1; float bd = 9 * rv.S;
    for (int i = 0; i < NFLY; i++) { float d = hypotf(ffx[i] - rv.x, ffy[i] - rv.y); if (ffb[i] > 0.25f && d < bd) { bd = d; best = i; } }
    return best;
}
static void choose(float t) {
    static const struct { int act; float w; } C[] = {
        { A_PREEN, 12 }, { A_CHEST, 8 }, { A_TILT, 10 }, { A_FIREFLY, 9 }, { A_WIPE, 6 }, { A_STRETCH, 6 }, { A_SIDESTEP, 6 }, { A_RUFFLE, 6 },
        { A_HOP, 6 }, { A_CALL, 6 }, { A_SCRATCH, 5 }, { A_TAILFAN, 4 }, { A_WINGSUP, 4 }, { A_SETTLE, 4 }, { A_ONELEG, 3 }, { A_STARE, 3 },
        { A_SHAKE, 3 }, { A_SLEEP, 1.5f }, { A_STARTLE, 1.5f }, { A_HANG, 1.2f }, { -1, 9 }, { -2, 4 }, { -3, 2 } };
    int n = sizeof C / sizeof *C, pick = A_PREEN;
    if (testact) pick = testact;
    else {
        float tot = 0; for (int i = 0; i < n; i++) tot += C[i].w;
        float r = frand() * tot;
        for (int i = 0; i < n; i++) { r -= C[i].w; if (r <= 0) { pick = C[i].act; break; } }
    }
    int solo = cr == &rav[0] && !rav[1].present;
    if (pick < 0 && !solo) pick = A_TILT;                 /* no leaving while company is here or coming */
    if (pick == -1) { int to = rnd() % NPERCH; if (to == rv.perch) to = (to + 1) % NPERCH; raven_fly_to(to); return; }
    if (pick == -2) { raven_fly_to(-2); return; }
    if (pick == -3) { raven_fly_to(-1); return; }
    if ((pick == A_HANG || pick == A_SIDESTEP) && (rv.perch >= 2 || !solo)) pick = A_RUFFLE;
    if (pick == A_FIREFLY && near_firefly() < 0) pick = A_TILT;
    act_start(pick);
    (void)t;
}

static void perched_update(float dt, float t) {
    float tg[NP]; memcpy(tg, PDEF, sizeof tg);
    int glances = 1;
    rv.x = perchx[rv.perch]; rv.y = perchy[rv.perch];
    if (rv.act == A_NONE && t > rv.next && !rv.paired) { choose(t); if (rv.state != PERCH) return; }
    if (rv.act != A_NONE) {
        float a = (rv.actt += dt), e = sinf(clampf(a / rv.adur, 0, 1) * PI), nib = sinf(a * 15);
        switch (rv.act) {
        case A_CALL: {
            float ph = fmodf(a, 0.62f) / 0.62f;
            tg[P_LEAN] = 0.42f; tg[P_HFWD] = 0.10f; tg[P_PUFF] = 1.08f; rv.yawT = 1; rv.tiltT = 0.05f; glances = 0;
            if (a > 0.25f && a < 2.1f) { tg[P_OPEN] = 0.42f * (ph < 0.6f ? sinf(ph / 0.6f * PI) : 0); tg[P_HFWD] += 0.06f * tg[P_OPEN]; }
        } break;
        case A_RUFFLE: tg[P_PUFF] = 1.0f + 0.22f * e + 0.035f * sinf(a * 42); break;
        case A_HOP:
            tg[P_CROUCH] = e; rv.p[P_CROUCH] = e;
            if (a > 0.17f && !rv.flipped) { rv.d = -rv.d; rv.flipped = 1; }
            break;
        case A_PREEN: rv.yawT = -0.8f; rv.tiltT = 0.5f; tg[P_HDX] = -0.30f; tg[P_HDY] = -0.17f + 0.03f * nib; tg[P_PUFF] = 1.06f; glances = 0; break;
        case A_CHEST: rv.yawT = 0.9f; rv.tiltT = -1.25f; tg[P_HDX] = -0.10f; tg[P_HDY] = -0.15f + 0.025f * nib; tg[P_PUFF] = 1.05f; glances = 0; break;
        case A_SCRATCH: tg[P_LEGUP] = 1; tg[P_HDY] = -0.14f; tg[P_HDX] = -0.03f; rv.yawT = 0.9f; rv.tiltT = -0.35f; tg[P_EYE] = 1; tg[P_LEAN] = 0.6f; glances = 0; break;
        case A_WIPE: case A_STASH:
            tg[P_LEAN] = 0.22f; tg[P_CROUCH] = 0.6f; tg[P_HDX] = 0.26f + 0.07f * sinf(a * 9); tg[P_HDY] = -0.60f; rv.yawT = 1; rv.tiltT = -0.55f; glances = 0;
            if (rv.act == A_STASH && a > 0.9f) rv.carry = 0;
            break;
        case A_STRETCH: tg[P_WINGL] = e > 0.3f ? 1 : 0; tg[P_FAN] = 0.5f * e; tg[P_LEAN] = 0.6f; break;
        case A_WINGSUP: tg[P_WINGUP] = e > 0.3f ? 1 : 0; tg[P_LEAN] = 0.45f; tg[P_HFWD] = 0.08f; tg[P_HDY] = -0.08f; break;
        case A_TAILFAN: tg[P_FAN] = 1; break;
        case A_SIDESTEP: rv.pfo = clampf(rv.pfo + rv.sdir * 0.11f * dt / rv.adur, -0.3f, 0.2f); tg[P_CROUCH] = 0.35f * fabsf(sinf(a * 10)); break;
        case A_SETTLE: tg[P_CROUCH] = 0.6f; tg[P_PUFF] = 1.13f; tg[P_LEAN] = 0.62f; break;
        case A_ONELEG: tg[P_ONELEG] = 1; tg[P_PUFF] = 1.06f; break;
        case A_SLEEP:
            tg[P_TUCK] = 1; tg[P_EYE] = 1; rv.yawT = -0.8f; rv.tiltT = 0.3f; tg[P_HDX] = -0.27f; tg[P_HDY] = -0.11f;
            tg[P_PUFF] = 1.13f + 0.02f * sinf(a * 1.1f); tg[P_CROUCH] = 0.55f; glances = 0;
            if (vis_on || breeze(t, rv.x) > 0.93f) rv.actt = rv.adur;        /* something wakes it */
            break;
        case A_TILT: rv.yawT = 0.9f; rv.tiltT = rv.sdir * 0.8f; tg[P_HDY] = rv.sdir > 0 ? 0.03f : -0.04f; glances = 0; break;
        case A_FIREFLY: {
            int f = near_firefly(); glances = 0;
            if (f < 0) { rv.actt = rv.adur; break; }
            look_at(ffx[f], ffy[f]);
            if (hypotf(ffx[f] - rv.x, ffy[f] - rv.y) < 2.2f * rv.S && a > 1 && !rv.step) rv.step = 1, rv.t = a;
            if (rv.step && a - rv.t < 0.3f) { tg[P_HFWD] = 0.22f; tg[P_OPEN] = 0.4f; }           /* a snap at it */
        } break;
        case A_STARE: rv.yawT = 0.05f; rv.tiltT = 0; glances = 0; break;
        case A_STARTLE:
            tg[P_CROUCH] = a < 0.5f ? 1 : 0; tg[P_WINGUP] = a < 0.35f ? 0.6f : 0; glances = 0;
            if (!rv.step) { rv.step = 1; rv.yawT = frand() < 0.5f ? 1 : -0.85f; rv.tiltT = 0.2f; }
            break;
        case A_SHAKE: tg[P_PUFF] = 1.16f; rv.yawT = 0.55f + 0.45f * sinf(a * 38); tg[P_ROT] = 0.05f * sinf(a * 45); rv.p[P_ROT] = tg[P_ROT]; glances = 0; break;
        case A_HANG:
            tg[P_ROT] = a < 2.6f ? PI : 0; tg[P_WINGUP] = a > 0.25f && a < 3.0f ? 0.45f : 0; rv.yawT = 1; rv.tiltT = 0.2f; glances = 0;
            break;
        case A_BOW: {
            float ph = fmodf(a, 0.7f) / 0.7f;
            tg[P_LEAN] = 0.2f; tg[P_PUFF] = 1.15f; tg[P_FAN] = 0.7f; tg[P_HDY] = -0.22f; tg[P_HDX] = 0.08f; rv.yawT = 1; rv.tiltT = -0.3f; glances = 0;
            if (a > 0.4f) tg[P_OPEN] = 0.3f * (ph < 0.5f ? sinf(ph * 2 * PI) : 0);
        } break;
        case A_BILL: tg[P_LEAN] = 0.5f; tg[P_HFWD] = 0.12f; tg[P_HDX] = 0.05f + 0.02f * nib; rv.yawT = 1; rv.tiltT = 0.08f * nib; glances = 0; break;
        case A_ALLO: tg[P_LEAN] = 0.4f; tg[P_HDX] = 0.30f; tg[P_HDY] = 0.02f + 0.03f * nib; rv.yawT = 1; rv.tiltT = -0.35f; glances = 0; break;
        case A_ALLOED: tg[P_EYE] = 1; tg[P_PUFF] = 1.1f; tg[P_HDY] = -0.07f; rv.yawT = 0.9f; rv.tiltT = -0.5f; glances = 0; break;
        }
        if (rv.actt >= rv.adur) { rv.act = A_NONE; rv.next = t + (testact ? 1.2f : rrange(4, 11)); rv.look = t + 0.3f; }
    } else if (vis_on && cr == &rav[0]) { look_at(vis_x, vis_y); glances = 0; }     /* something is passing */
    if (glances && t > rv.look) {                        /* birds look in quick, separate glances */
        float r = frand();
        rv.yawT = r < 0.45f ? 1.0f : r < 0.65f ? 0.82f : r < 0.82f ? 0.35f : -0.85f;
        rv.tiltT = rrange(-0.38f, 0.30f); rv.look = t + rrange(0.7f, 4.2f);
    }
    float g = breeze(t, rv.x);                           /* a gust: get low and hold on */
    if (g > 0.78f && tg[P_ROT] == 0) { float u = (g - 0.78f) * 4; tg[P_LEAN] -= 0.16f * u; tg[P_CROUCH] += 0.5f * u; tg[P_PUFF] += 0.05f * u; }
    for (int i = 0; i < NP; i++) rv.p[i] += (tg[i] - rv.p[i]) * fminf(1, PRATE[i] * dt);
    float q = fminf(1, 16 * dt);
    rv.yaw += (rv.yawT - rv.yaw) * q; rv.tilt += (rv.tiltT - rv.tilt) * q;
}

/* on the forest floor: walk a little, peck, look up, and sometimes find something to carry off */
static void ground_update(float dt, float t) {
    float tg[NP]; memcpy(tg, PDEF, sizeof tg);
    rv.x = rv.gx; rv.y = ground_top(rv.gx) + 1;
    if (rv.act == A_NONE && t > rv.next) {
        if (rv.steps <= 0) {
            if (rnd() % 5 < 2) rv.carry = 1 + rnd() % 2;
            int to = rnd() % NPERCH; raven_fly_to(to); return;
        }
        rv.steps--;
        if (rnd() & 1) { act_start(A_WALK); rv.gxT = clampf(rv.gx + srand1() * 3.5f * rv.S, W * 0.24f, W * 0.84f); rv.d = rv.gxT > rv.gx ? 1 : -1; rv.adur = 99; }
        else act_start(A_PECK);
    }
    if (rv.act == A_WALK) {
        float st = 1.0f * rv.S * dt; rv.walkph += dt * 9; rv.yawT = 1; rv.tiltT = -0.1f;
        tg[P_HFWD] = 0.05f * sinf(rv.walkph * 2); tg[P_LEAN] = 0.55f;
        if (fabsf(rv.gxT - rv.gx) <= st) { rv.gx = rv.gxT; rv.act = A_NONE; rv.next = t + rrange(0.4f, 1.6f); }
        else rv.gx += st * rv.d;
    } else if (rv.act == A_PECK) {
        float a = (rv.actt += dt), pk = fabsf(sinf(a / rv.adur * 2 * PI));
        tg[P_LEAN] = 0.70f - 0.52f * pk; tg[P_HDX] = 0.28f * pk; tg[P_HDY] = -0.72f * pk; tg[P_CROUCH] = 0.4f * pk; rv.yawT = 1; rv.tiltT = -0.75f * pk;
        if (a >= rv.adur) { rv.act = A_NONE; rv.next = t + rrange(0.5f, 2.0f); rv.look = t; }
    } else if (t > rv.look) { rv.yawT = frand() < 0.6f ? 1 : -0.85f; rv.tiltT = rrange(-0.2f, 0.35f); rv.look = t + rrange(0.5f, 1.5f); }
    for (int i = 0; i < NP; i++) rv.p[i] += (tg[i] - rv.p[i]) * fminf(1, (i == P_HDX || i == P_HDY || i == P_LEAN ? 18 : PRATE[i]) * dt);
    float q = fminf(1, 16 * dt);
    rv.yaw += (rv.yawT - rv.yaw) * q; rv.tilt += (rv.tiltT - rv.tilt) * q;
}

static void raven_update(float dt, float t) {
    rv.S = H * (cr == &rav[0] ? 0.098f : 0.090f);
    if ((rnd() & 255) == 0) rv.blink = 6; else if (rv.blink) rv.blink--;
    if (rv.state == AWAY) {
        rv.away -= dt;
        if (cr == &rav[1]) { rv.present = 0; return; }
        if (rv.away <= 0) { rv.x = rv.endx; rv.y = rv.endy; raven_fly_to(rnd() % NPERCH); }
        return;
    }
    if (rv.state == GROUND) { ground_update(dt, t); return; }
    if (rv.state == PERCH) { perched_update(dt, t); return; }
    rv.t += dt; float u = rv.t / rv.dur; if (u > 1) u = 1;
    float e = u * u * (3 - 2 * u), m = 1 - e, ex, ey; perch_point(rv.to, &ex, &ey);
    float px = m * m * m * rv.p0x + 3 * m * m * e * rv.c1x + 3 * m * e * e * rv.c2x + e * e * e * ex;
    float py = m * m * m * rv.p0y + 3 * m * m * e * rv.c1y + 3 * m * e * e * rv.c2y + e * e * e * (ey - 0.45f * rv.S * (rv.to != -1));
    float vx = px - rv.x, vy = py - rv.y; rv.x = px; rv.y = py;
    float want = clampf(atan2f(-vy, fabsf(vx) + 0.3f), -0.5f, 0.6f);
    int landing = rv.to != -1;
    if (u > 0.86f && landing) want = 0.55f;                            /* flare to land */
    rv.pitch += (want - rv.pitch) * fminf(1, 6 * dt);
    int glide = rv.dur > 2.6f && u > 0.42f && u < 0.66f;
    rv.rollf = rv.rollit && u > 0.40f && u < 0.62f ? cosf((u - 0.40f) / 0.22f * 2 * PI) : 1;
    if (u > 0.9f && landing) rv.flap = 0.95f + 0.25f * sinf(t * 26);
    else if (glide || rv.rollf < 0.99f) rv.flap += (0.16f - rv.flap) * fminf(1, 8 * dt);
    else rv.flap = 0.18f + 1.02f * sinf(rv.t * 2 * PI * 3.3f);
    if (u >= 1) {
        rv.rollf = 1;
        for (int i = 0; i < NP; i++) rv.p[i] = PDEF[i];
        rv.p[P_CROUCH] = 1; rv.p[P_LEAN] = 0.5f; rv.yaw = rv.yawT = 1; rv.act = A_NONE; rv.look = t + 0.6f;
        if (rv.to == -1) { rv.state = AWAY; rv.away = rrange(12, 34); }
        else if (rv.to == -2) { rv.state = GROUND; rv.steps = 3 + rnd() % 5; rv.next = t + 0.8f; }
        else { rv.state = PERCH; rv.perch = rv.to; rv.next = t + rrange(4, 9); if (rv.carry) { act_start(A_STASH); } }
    }
}

/* a second raven drops in now and then; the two bow, touch bills and preen each other */
static float gtimer = 300, gstay, gnext;
static void ravens_update(float dt, float t) {
    Raven *a = &rav[0], *b = &rav[1];
    cr = a; raven_update(dt, t);
    if (b->present) { cr = b; raven_update(dt, t); }
    cr = a;
    if (!b->present) {
        gtimer -= dt;
        if (gtimer <= 0) {
            if (a->state == PERCH && a->perch == 0 && a->act == A_NONE) {
                cr = b; memset(b, 0, sizeof *b); for (int i = 0; i < NP; i++) b->p[i] = PDEF[i];
                b->present = 1; b->S = H * 0.090f; b->x = -4 * b->S; b->y = H * 0.2f; b->yaw = b->yawT = 1; b->rollf = 1;
                raven_fly_to(3); gstay = rrange(28, 50); gnext = 0; cr = a;
                a->pfo = 0;
            } else gtimer = 8;
        }
        a->paired = 0;
        return;
    }
    if (b->state != PERCH) { a->paired = b->paired = 0; return; }
    int together = a->state == PERCH && a->perch == 0;
    a->paired = b->paired = together;
    gstay -= dt;
    if (gstay <= 0 || (!together && gstay < 20)) {
        if (b->act == A_NONE) { cr = b; raven_fly_to(-1); cr = a; a->paired = 0; a->next = t + 3; gtimer = testguest ? 6 : rrange(240, 520); }
        return;
    }
    if (!together) return;
    a->d = -1; b->d = 1;                                   /* facing each other */
    if (a->act == A_NONE && b->act == A_NONE) {
        if (gnext == 0) gnext = t + 1.5f;
        if (t > gnext) {
            int r = rnd() % 5; Raven *x = rnd() & 1 ? a : b, *y = x == a ? b : a;
            if (r == 0) { cr = x; act_start(A_BOW); cr = y; act_start(A_BOW); y->actt = -0.5f; }
            else if (r == 1) { cr = a; act_start(A_BILL); cr = b; act_start(A_BILL); }
            else if (r == 2) { cr = x; act_start(A_ALLO); cr = y; act_start(A_ALLOED); }
            else if (r == 3) { cr = x; act_start(A_CALL); }
            else { cr = x; act_start(A_RUFFLE); }
            cr = a; gnext = t + rrange(4, 8);
        }
    }
}
static void ravens_draw(float t) {
    for (int i = 1; i >= 0; i--) {
        cr = &rav[i];
        if (i == 1 && !rv.present) continue;
        if (rv.state == PERCH || rv.state == GROUND) raven_perched(t); else if (rv.state == FLY) raven_flying();
    }
    cr = &rav[0];
}

/* light the foreground from the moon's side and lay it over the picture */
static void hero_light(void) {
    int y0 = hy0 < 0 ? 0 : hy0, y1 = hy1 >= H ? H - 1 : hy1, x0 = hx0 < 0 ? 0 : hx0, x1 = hx1 >= W ? W - 1 : hx1;
    for (int y = y0; y <= y1; y++) {
        const uint8_t *m = hm + y * W; uint8_t *d = fb + y * W;
        for (int x = x0; x <= x1; x++) {
            uint8_t v = m[x]; if (!v) continue;
            if (v == 3) { d[x] = 6 | 1; continue; }
            if (v == 2) { d[x] = 44; continue; }
            if (v == 6) { d[x] = 150; continue; }
            if (v == 5) { d[x] = 2; continue; }
            int lx = x < moonx ? 1 : -1, out;
            int ax = x + lx, ay = y - 1, bx = x + 2 * lx, by = y - 2;
            if (ax < 0 || ax >= W || ay < 0) out = 0;
            else if (!m[ax - W]) out = 1;
            else if (bx >= 0 && bx < W && by >= 0 && !hm[by * W + bx]) out = 2;
            else out = 0;
            if (v == 1 && out && (hash2(x >> 1, y / 5) % 5) < 2) out = 0;          /* bark breaks the lit edge */
            d[x] = out == 1 ? (v == 4 ? 70 : 34) : out == 2 ? (v == 4 ? 30 : 16) : 2;
        }
    }
}

/* fireflies, between the middle trees and the near ones */
static void fireflies(float t) {
    for (int i = 0; i < NFLY; i++) {
        float a = i * 2.39996f, p = sinf(t * (0.5f + 0.045f * i) + a * 3);
        p = p > 0 ? p * p * p : 0;
        float x = W * (0.5f + 0.47f * sinf(a * 5 + t * 0.021f * (1 + (i & 3)) + 0.9f * sinf(t * 0.13f + a)));
        float y = H * (0.60f + 0.20f * sinf(a * 7 + t * 0.05f) + 0.03f * sinf(t * 0.6f + a));
        ffx[i] = x; ffy[i] = y; ffb[i] = p;
        if (p < 0.08f) continue;
        int xi = (int)x, yi = (int)y; if (xi < 1 || xi >= W - 1 || yi < 1 || yi >= H - 1) continue;
        int v = fb[yi * W + xi] + (int)(p * 215); fb[yi * W + xi] = (uint8_t)(v > 254 ? 254 : v) | 1;
        if (p > 0.75f && K > 0.8f) { v = fb[yi * W + xi + 1] + (int)(p * 120); fb[yi * W + xi + 1] = (uint8_t)(v > 254 ? 254 : v) | 1; }
    }
}

/* ---------- visitors: small drawings loaded from ~/.config/aeris/ravenwood/NAME.visitor ----------
   Each file is a few "key = value" lines and then one or more frames, each starting with a line
   that says "frame". A frame is a drawing, one character per dot, facing right:
       #  body (dark)     :  stippled (leaves, fur)     *  light (an eye, a spark)     anything else: see-through
   Keys: layer (-1 behind everything, 0 far .. 3 near, 4 in front), path (walk | fly | fall),
   speed (dots a second), every (seconds between visits, on average), height (fly: 0 top .. 1 bottom),
   bob (fly: up-and-down, dots), angle (fly: degrees downward), count (how many at once),
   frametime (seconds per frame), stops (walk: pauses on the way), stoptime (seconds each),
   stopframes (which frames to show while paused, e.g. "4 5"), tone (grey of the body), scale.
   The folder is read again before every visit, so a new file needs no restart. */
#include <dirent.h>

/* --light: a pale scene for a light desktop. Every shade goes through a table
 * from grey to paper and ink: 0 is ink (#2b2a27), 255 is paper (#f4f1ea). */
static int light = 0;
static uint8_t lut_r[256], lut_g[256], lut_b[256];
static void light_table(int curve) {
    for (int v = 0; v < 256; v++) {
        double f = v / 255.0;
        if (curve) { f = pow(v / 160.0, 0.6); if (f > 1) f = 1; }   /* fog lifts to paper, shadows stay ink */
        lut_r[v] = (uint8_t)(43 + (244 - 43) * f + 0.5);
        lut_g[v] = (uint8_t)(42 + (241 - 42) * f + 0.5);
        lut_b[v] = (uint8_t)(39 + (234 - 39) * f + 0.5);
    }
}
static char *put_num(char *o, int n);
static char *put_rgb(char *o, int v) {
    if (v < 0) v = 0; if (v > 255) v = 255;
    if (!light) { o = put_num(o, v); *o++ = ';'; o = put_num(o, v); *o++ = ';'; return put_num(o, v); }
    o = put_num(o, lut_r[v]); *o++ = ';'; o = put_num(o, lut_g[v]); *o++ = ';'; return put_num(o, lut_b[v]);
}

typedef struct {
    char name[64]; int layer, path, count, nf, w, h, stops, nstop, stopf[4], ncyc, cyc[16], tone;
    float speed, every, height, bob, angle, frametime, stoptime, scale; char *fr[16];
} Visitor;
#define MAXVIS 40
#define MAXN 24
static Visitor vis[MAXVIS]; static int nvis;
static struct { int on, idx, dir, n, stopi; float t, x[MAXN], y[MAXN], ph[MAXN], stopx[4], stopt, next; } vs;
static char testvis[64];

static void vis_load(void) {
    for (int i = 0; i < nvis; i++) for (int f = 0; f < vis[i].nf; f++) free(vis[i].fr[f]);
    nvis = 0;
    char dir[512]; const char *home = getenv("HOME"); if (!home) return;
    snprintf(dir, sizeof dir, "%s/.config/aeris/ravenwood", home);
    DIR *d = opendir(dir); if (!d) return;
    struct dirent *de;
    while ((de = readdir(d)) && nvis < MAXVIS) {
        size_t l = strlen(de->d_name);
        if (l < 9 || l > 60 || strcmp(de->d_name + l - 8, ".visitor")) continue;
        char path[800]; snprintf(path, sizeof path, "%s/%s", dir, de->d_name);
        FILE *f = fopen(path, "r"); if (!f) continue;
        Visitor *v = &vis[nvis]; memset(v, 0, sizeof *v);
        memcpy(v->name, de->d_name, l - 8);
        v->layer = 2; v->count = 1; v->speed = 20; v->every = 300; v->height = 0.4f; v->frametime = 0.15f; v->stoptime = 3; v->scale = 1; v->tone = -1;
        static char rowbuf[160][260]; int nr = 0, inframe = 0; char line[300];
        for (;;) {
            char *got = fgets(line, sizeof line, f);
            int isframe = got && !strncmp(line, "frame", 5);
            if ((!got || isframe) && inframe && nr > 0 && v->nf < 16) {          /* close the frame being read */
                int w = 0; for (int r = 0; r < nr; r++) { int n = (int)strlen(rowbuf[r]); if (n > w) w = n; }
                if (v->nf == 0) { v->w = w; v->h = nr; }
                char *px = calloc((size_t)v->w * v->h, 1);
                for (int r = 0; r < nr && r < v->h; r++) for (int c = 0; rowbuf[r][c] && c < v->w; c++) px[r * v->w + c] = rowbuf[r][c];
                v->fr[v->nf++] = px;
            }
            if (!got) break;
            line[strcspn(line, "\r\n")] = 0;
            if (isframe) { inframe = 1; nr = 0; continue; }
            if (inframe) { if (nr < 160) { strncpy(rowbuf[nr], line, 259); rowbuf[nr][259] = 0; nr++; } continue; }
            char *eq = strchr(line, '='); if (!eq || line[0] == '#') continue;
            *eq = 0; char key[40] = "", *val = eq + 1; sscanf(line, "%39s", key); while (*val == ' ') val++;
            char *hash = strchr(val, '#'); if (hash) *hash = 0;
            if (!strcmp(key, "layer")) v->layer = atoi(val);
            else if (!strcmp(key, "path")) v->path = !strncmp(val, "fly", 3) ? 1 : !strncmp(val, "fall", 4) ? 2 : 0;
            else if (!strcmp(key, "speed")) v->speed = atof(val);
            else if (!strcmp(key, "every")) v->every = atof(val);
            else if (!strcmp(key, "height")) v->height = atof(val);
            else if (!strcmp(key, "bob")) v->bob = atof(val);
            else if (!strcmp(key, "angle")) v->angle = atof(val);
            else if (!strcmp(key, "count")) v->count = atoi(val);
            else if (!strcmp(key, "frametime")) v->frametime = atof(val);
            else if (!strcmp(key, "stops")) v->stops = atoi(val);
            else if (!strcmp(key, "stoptime")) v->stoptime = atof(val);
            else if (!strcmp(key, "tone")) v->tone = atoi(val);
            else if (!strcmp(key, "scale")) v->scale = atof(val);
            else if (!strcmp(key, "stopframes")) v->nstop = sscanf(val, "%d %d %d %d", &v->stopf[0], &v->stopf[1], &v->stopf[2], &v->stopf[3]);
        }
        fclose(f);
        if (v->nstop < 0) v->nstop = 0;
        for (int i = 0; i < v->nf; i++) {                  /* the frames that are not for pausing make the cycle */
            int stop = 0; for (int k = 0; k < v->nstop; k++) if (v->stopf[k] == i) stop = 1;
            if (!stop) v->cyc[v->ncyc++] = i;
        }
        if (v->count < 1) v->count = 1; if (v->count > MAXN) v->count = MAXN;
        if (v->stops > 4) v->stops = 4; if (v->every < 5) v->every = 5; if (v->frametime < 0.02f) v->frametime = 0.02f;
        if (v->layer < -1) v->layer = -1; if (v->layer > 4) v->layer = 4;
        if (v->nf > 0 && v->ncyc > 0 && v->w > 0) nvis++; else for (int i = 0; i < v->nf; i++) free(v->fr[i]);
    }
    closedir(d);
}
static float vis_ground(const Visitor *v, float x) {
    return v->layer >= 4 ? ground_top(x) + 2 : v->layer >= 0 ? layer_gy[v->layer] + 1 : H * 0.78f;
}
static void vis_start(float t) {
    vis_load();
    vs.next = t + 30;
    if (!nvis) return;
    int pick = -1; float tot = 0;
    for (int i = 0; i < nvis; i++) { tot += 1.0f / vis[i].every; if (testvis[0] && !strcmp(vis[i].name, testvis)) pick = i; }
    if (pick < 0) { float r = frand() * tot; for (int i = 0; i < nvis; i++) { r -= 1.0f / vis[i].every; pick = i; if (r <= 0) break; } }
    Visitor *v = &vis[pick]; float f = v->scale * K;
    vs.on = 1; vs.idx = pick; vs.t = 0; vs.dir = rnd() & 1 ? 1 : -1; vs.n = v->count; vs.stopi = 0; vs.stopt = 0;
    for (int i = 0; i < v->stops; i++) vs.stopx[i] = W * (0.2f + 0.6f * (i + frand()) / v->stops);
    for (int i = 0; i < vs.n; i++) {
        vs.ph[i] = frand() * 6.28f;
        if (v->path == 2) { vs.x[i] = W * rrange(0.05f, 0.95f); vs.y[i] = -rrange(0, 0.6f) * H - v->h * f; }
        else {
            float lag = i * v->w * f * rrange(1.3f, 2.6f);
            vs.x[i] = vs.dir > 0 ? -v->w * f - lag : W + lag;
            vs.y[i] = v->path == 1 ? H * v->height + (i ? srand1() * 0.06f * H : 0) : 0;
        }
    }
    vs.next = t + 1e9f;
}
static void vis_update(float dt, float t) {
    vis_on = 0;
    if (!vs.on) { if (t > vs.next) vis_start(t); return; }
    Visitor *v = &vis[vs.idx]; float f = v->scale * K, sp = v->speed * K * dt; int alive = 0;
    vs.t += dt;
    if (vs.stopt > 0) { vs.stopt -= dt; sp = 0; }
    for (int i = 0; i < vs.n; i++) {
        if (v->path == 2) {
            float gy = vis_ground(v, vs.x[i]) - v->h * f;
            if (vs.y[i] < gy) { vs.y[i] += sp * (0.7f + 0.3f * sinf(vs.ph[i])); vs.x[i] += sinf(vs.t * 1.4f + vs.ph[i]) * 14 * K * dt - 6 * K * dt; alive = 1; }
            continue;
        }
        vs.x[i] += sp * vs.dir;
        if (v->path == 1) vs.y[i] += sp * tanf(v->angle * PI / 180);
        if (vs.dir > 0 ? vs.x[i] < W + 2 : vs.x[i] > -v->w * f - 2) alive = 1;
    }
    if (v->path == 0 && vs.stopi < v->stops && vs.stopt <= 0) {      /* reached the next place to pause? */
        float sx = vs.dir > 0 ? vs.stopx[vs.stopi] : vs.stopx[v->stops - 1 - vs.stopi];
        if (vs.dir > 0 ? vs.x[0] >= sx : vs.x[0] <= sx) { vs.stopt = v->stoptime * rrange(0.7f, 1.4f); vs.stopi++; }
    }
    if (!alive) {
        vs.on = 0;
        float tot = 0; for (int i = 0; i < nvis; i++) tot += 1.0f / vis[i].every;
        vs.next = t + (testvis[0] ? 3 : rrange(0.5f, 1.5f) / tot);
        return;
    }
    if (v->layer >= 1 && v->path != 2 && vs.x[0] > 0 && vs.x[0] < W) { vis_on = 1; vis_x = vs.x[0] + v->w * f * 0.5f; vis_y = (v->path == 1 ? vs.y[0] : vis_ground(v, vs.x[0]) - v->h * f * 0.5f); }
}
static void vis_draw(int l, float t) {
    if (!vs.on || vis[vs.idx].layer != l) return;
    const Visitor *v = &vis[vs.idx]; float f = v->scale * K, inv = 1.0f / f;
    int ow = (int)(v->w * f), oh = (int)(v->h * f);
    int mul = l < 0 ? 140 : l < 2 ? layer[l].mul : 0, tone = v->tone >= 0 ? v->tone : l == 2 ? 26 : l == 3 ? 8 : 2;
    for (int i = 0; i < vs.n; i++) {
        int fi;
        if (vs.stopt > 0 && v->nstop > 0) fi = v->stopf[(int)(vs.t / 1.4f) % v->nstop];
        else fi = v->cyc[(int)(vs.t / v->frametime + (v->path == 2 || v->count > 1 ? vs.ph[i] * 3 : 0)) % v->ncyc];
        if (fi < 0 || fi >= v->nf) fi = 0;
        const char *px = v->fr[fi];
        float bob = v->path == 1 ? v->bob * K * sinf(vs.t * 2.2f + vs.ph[i]) : 0;
        int X = (int)vs.x[i], Y = v->path == 0 ? (int)(vis_ground(v, vs.x[i] + ow * 0.5f) - oh) : (int)(vs.y[i] + bob);
        if (v->path == 2 && vs.y[i] >= vis_ground(v, vs.x[i]) - oh) continue;      /* landed: gone into the litter */
        for (int dy = 0; dy < oh; dy++) {
            int y = Y + dy; if (y < 0 || y >= H) continue;
            const char *row = px + (int)(dy * inv) * v->w;
            for (int dx = 0; dx < ow; dx++) {
                int x = X + (vs.dir > 0 ? dx : ow - 1 - dx); if (x < 0 || x >= W) continue;
                char c = row[(int)(dx * inv)]; uint8_t *d = fb + y * W + x;
                if (c == '#') *d = mul ? (uint8_t)((*d * mul) >> 8) & ~1 : (uint8_t)(tone & ~1);
                else if (c == ':') *d = (mul ? (uint8_t)((*d * mul) >> 8) & ~1 : (uint8_t)(tone & ~1)) | 1;
                else if (c == '*') { int q = *d + 150; *d = (uint8_t)(q > 254 ? 254 : q) | 1; }
            }
        }
    }
    (void)t;
}

/* ---------- from picture to characters ---------- */
static inline char *put_utf8(char *o, uint32_t c) {
    if (c < 0x80) *o++ = c;
    else if (c < 0x800) { *o++ = 0xC0 | (c >> 6); *o++ = 0x80 | (c & 0x3F); }
    else if (c < 0x10000) { *o++ = 0xE0 | (c >> 12); *o++ = 0x80 | ((c >> 6) & 0x3F); *o++ = 0x80 | (c & 0x3F); }
    else { *o++ = 0xF0 | (c >> 18); *o++ = 0x80 | ((c >> 12) & 0x3F); *o++ = 0x80 | ((c >> 6) & 0x3F); *o++ = 0x80 | (c & 0x3F); }
    return o;
}
static inline char *put_num(char *o, int v) { memcpy(o, num[v], 4); return o + numlen[v]; }
#define QSTEP 4

static size_t compose(int full) {
    char *o = out;
    memcpy(o, "\x1b[?2026h", 8); o += 8;
    int curfg = -1, curbg = -1, cr = -1, cc = -1, slen = (int)strlen(statline);
    for (int r = 0; r < rows; r++) {
        const uint8_t *p0 = fb + (r * 4) * W, *p1 = p0 + W, *p2 = p1 + W, *p3 = p2 + W;
        for (int c = 0; c < cols; c++) {
            int idx = r * cols + c, x = c * 2;
            int v[8] = { p0[x], p0[x + 1], p1[x], p1[x + 1], p2[x], p2[x + 1], p3[x], p3[x + 1] };
            int mn = 255, mx = 0;
            for (int k = 0; k < 8; k++) { int q = v[k] & ~1; if (q < mn) mn = q; if (q > mx) mx = q; }
            uint32_t g = ' '; int fg = 0, bg;
            if (r == 0 && c < slen) { g = statline[c]; fg = 220; bg = 0; }
            else if (mx - mn < 7) { bg = (mn + mx + QSTEP) / 2 / QSTEP * QSTEP; }
            else {
                int th = (mn + mx) >> 1, mask = 0, sh = 0, sl = 0, nh = 0, th_h = 0, th_l = 0;
                for (int k = 0; k < 8; k++) {
                    int q = v[k] & ~1;
                    if (q > th) { mask |= 1 << k; sh += q; nh++; th_h += v[k] & 1; } else { sl += q; th_l += v[k] & 1; }
                }
                int hi = (sh / nh + QSTEP / 2) / QSTEP * QSTEP, lo = (sl / (8 - nh) + QSTEP / 2) / QSTEP * QSTEP;
                if (hi > 255) hi = 255;
                if (hi == lo) { bg = lo; }
                else if (th_h * 2 > nh) { g = 0x2800 + BRAILLE[mask]; fg = hi; bg = lo; }                    /* light specks */
                else if (th_l * 2 > 8 - nh) { g = 0x2800 + BRAILLE[mask ^ 255]; fg = lo; bg = hi; }         /* dark leaves */
                else { g = OCT[mask]; fg = hi; bg = lo; }
            }
            if (g == ' ') fg = 0;
            if (!full && pg[idx] == g && pf[idx] == fg && pb[idx] == bg) continue;
            pg[idx] = g; pf[idx] = fg; pb[idx] = bg;
            if (cr != r || cc != c) { *o++ = 0x1b; *o++ = '['; o = put_num(o, r + 1); *o++ = ';'; o = put_num(o, c + 1); *o++ = 'H'; }
            if (bg != curbg) { memcpy(o, "\x1b[48;2;", 7); o += 7; o = put_rgb(o, bg); *o++ = 'm'; curbg = bg; }
            if (g != ' ' && fg != curfg) { memcpy(o, "\x1b[38;2;", 7); o += 7; o = put_rgb(o, fg); *o++ = 'm'; curfg = fg; }
            o = put_utf8(o, g);
            cr = r; cc = c + 1;
        }
    }
    memcpy(o, "\x1b[?2026l", 8); o += 8;
    return o - out;
}

static void render(float t, int frame) {
    const float cam = 0;      /* the viewpoint stands still: depth shows in how each layer answers the wind and the mist */
    if (frame % 8 == 0) fog_update(0, t); else if (frame % 8 == 4) fog_update(1, t);
    memcpy(fb, sky, (size_t)W * H);
    vis_draw(-1, t);
    layer_blit(&layer[0], cam, t); vis_draw(0, t);
    layer_blit(&layer[1], cam, t); vis_draw(1, t);
    fog_apply(0, 1.0f);
    layer_blit(&layer[2], cam, t); vis_draw(2, t);
    fog_apply(1, 1.0f);
    fireflies(t);
    layer_blit(&layer[3], cam, t); vis_draw(3, t);
    fog_apply(1, 0.35f);
    memset(hm, 0, (size_t)W * H); hx0 = W; hx1 = -1; hy0 = H; hy1 = -1;
    perch_sel = rav[0].state == PERCH ? rav[0].perch : -1; perch_off = rav[0].pfo;
    hero_draw(t, cam);
    ravens_draw(t);
    grass_draw(t, cam);
    hero_light();
    vis_draw(4, t);
}

/* ---------- terminal ---------- */
static volatile sig_atomic_t quit, resized = 1, woke;
static void on_sig(int s) { if (s == SIGWINCH) resized = 1; else if (s == SIGCONT) woke = 1; else quit = 1; }
static struct termios old_tio; static int tio_saved;
static void term_restore(void) {
    static const char s[] = "\x1b[0m\x1b[?7h\x1b[?25h\x1b[?1049l";
    if (write(1, s, sizeof s - 1) < 0) {}
    if (tio_saved) tcsetattr(0, TCSANOW, &old_tio);
}
static void resize(int fc, int fr) {
    struct winsize ws = { 0 };
    cols = fc; rows = fr; asp = 1.0f;
    if (!fc && ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        cols = ws.ws_col; rows = ws.ws_row;
        if (ws.ws_xpixel > 0 && ws.ws_ypixel > 0) asp = ((float)ws.ws_xpixel / cols / 2.0f) / ((float)ws.ws_ypixel / rows / 4.0f);
    }
    if (cols < 40) cols = 40; if (rows < 12) rows = 12; if (cols > 998) cols = 998; if (rows > 998) rows = 998;
    W = cols * 2; H = rows * 4; K = W / 674.0f;
    free(fb); free(sky); free(skycell); free(hm); free(fogA[0]); free(fogA[1]); free(fogC); free(arow); free(crow);
    free(pg); free(pf); free(pb); free(out);
    fb = calloc((size_t)W * H, 1); sky = calloc((size_t)W * H, 1); hm = calloc((size_t)W * H, 1);
    skycell = calloc(cols * rows, 1); fogA[0] = calloc(cols * rows, 1); fogA[1] = calloc(cols * rows, 1); fogC = calloc(cols * rows, 1);
    arow = calloc(W, 1); crow = calloc(W, 1);
    pg = calloc(cols * rows, sizeof(uint32_t)); pf = calloc(cols * rows, 1); pb = calloc(cols * rows, 1);
    out = malloc((size_t)cols * rows * 56 + 64);
    uint32_t keep = rng_s; rng_s = 0xf07e57u;          /* the same forest every time */
    sky_build(); layers_build(); hero_build();
    rng_s = keep;
    fog_update(0, 0); fog_update(1, 0);
    memset(hm, 0, (size_t)W * H); hero_draw(0, 0);     /* so the perches have places */
    if (rav[0].state == PERCH) { rav[0].x = perchx[rav[0].perch]; rav[0].y = perchy[rav[0].perch]; }
}
static void write_all(const char *b, size_t n) {
    while (n > 0 && !quit) { ssize_t k = write(1, b, n); if (k < 0) { if (quit) return; continue; } b += k; n -= k; }
}

int main(int argc, char **argv) {
    int fps = 60, stats = 0, bench = 0, fixed_fps = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--fps") && i + 1 < argc) { fps = atoi(argv[++i]); fixed_fps = 1; }
        else if (!strcmp(argv[i], "--seed") && i + 1 < argc) rng_s = (uint32_t)atoi(argv[++i]) * 2654435761u + 1;
        else if (!strcmp(argv[i], "--stats")) stats = 1;
        else if (!strcmp(argv[i], "--light")) { light = 1; light_table(1); }
        else if (!strcmp(argv[i], "--act") && i + 1 < argc) { i++; for (int k = 1; k < NACT; k++) if (!strcmp(argv[i], ACTNAME[k])) testact = k; if (!strcmp(argv[i], "ground")) testact = -2; if (!strcmp(argv[i], "fly")) testact = -1; }
        else if (!strcmp(argv[i], "--guest")) testguest = 1;
        else if (!strcmp(argv[i], "--visitor") && i + 1 < argc) snprintf(testvis, sizeof testvis, "%s", argv[++i]);
        else if (!strcmp(argv[i], "--bench") && i + 1 < argc) bench = atoi(argv[++i]);
        else { fprintf(stderr, "ravenwood: a misty moonlit forest with one raven\nusage: ravenwood [--fps N] [--seed N] [--stats] [--bench FRAMES]\n"); return 2; }
    }
    if (fps < 5) fps = 5; if (fps > 120) fps = 120;
    for (int i = 0; i < 1000; i++) numlen[i] = (uint8_t)sprintf(num[i], "%d", i);
    for (int m = 0; m < 256; m++) {
        static const uint8_t map[8] = { 0x01, 0x08, 0x02, 0x10, 0x04, 0x20, 0x40, 0x80 };
        uint8_t b = 0; for (int k = 0; k < 8; k++) if (m >> k & 1) b |= map[k];
        BRAILLE[m] = b;
    }
    if (!bench) {
        if (rng_s == 0x9e3779b9u) rng_s ^= (uint32_t)time(NULL) * 2246822519u;
        struct sigaction sa = { 0 }; sa.sa_handler = on_sig;
        sigaction(SIGINT, &sa, 0); sigaction(SIGTERM, &sa, 0); sigaction(SIGHUP, &sa, 0); sigaction(SIGWINCH, &sa, 0); sigaction(SIGCONT, &sa, 0);
        if (tcgetattr(0, &old_tio) == 0) { struct termios t = old_tio; t.c_lflag &= ~(ECHO | ICANON); tcsetattr(0, TCSANOW, &t); tio_saved = 1; }
        static const char s[] = "\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[2J";
        write_all(s, sizeof s - 1);
        atexit(term_restore);
    }
    rv.state = PERCH; rv.perch = 0; rv.d = 1; rv.yaw = rv.yawT = 1; rv.rollf = 1; rv.next = 9; rv.look = 1;
    for (int i = 0; i < NP; i++) rv.p[i] = PDEF[i];
    resize(bench ? 336 : 0, bench ? 92 : 0); resized = 0;
    double simt = bench ? 0 : rnd() % 2000;
    if (testact) rv.next = 2;
    if (testguest) gtimer = 3;
    rv.next += simt; rv.look += simt; vs.next = simt + (testvis[0] ? 2 : rrange(40, 100));
    if (bench) {
        double t0 = now_s(), tr = 0, tc = 0; size_t bytes = 0;
        for (int f = 0; f < bench; f++) {
            double a = now_s(); simt += 1.0 / 60; vis_update(1.0f / 60, simt); ravens_update(1.0f / 60, simt); render(simt, f);
            double b = now_s(); bytes += compose(0); double c = now_s(); tr += b - a; tc += c - b;
        }
        printf("%dx%d cells: paint %.2f ms, compose %.2f ms, %.1f kB/frame, total %.2f ms/frame\n", cols, rows,
               tr / bench * 1e3, tc / bench * 1e3, bytes / 1024.0 / bench, (now_s() - t0) / bench * 1e3);
        return 0;
    }
    double last = now_s(), next = last, ema = 0, shown = last; int frame = 0, slow = 0, full = 1, drawn = 0;
    while (!quit) {
        double t = now_s(); float dt = (float)(t - last); last = t;
        if (woke) { woke = 0; full = 1; dt = 0; next = t; }
        if (dt > 0.05f) dt = 0.05f;
        if (resized) { resized = 0; resize(0, 0); full = 1; write_all("\x1b[2J", 4); }
        simt += dt;
        vis_update(dt, (float)simt);
        ravens_update(dt, (float)simt);
        render((float)simt, frame);
        size_t n = compose(full); full = 0;
        write_all(out, n);
        double work = now_s() - t; ema += (work - ema) * 0.05; frame++; drawn++;
        if (stats && t - shown >= 0.5) {
            snprintf(statline, sizeof statline, " %dx%d  %4.1f fps (target %d)  work %4.1f ms  %5.1f kB  raven %s  visitor %s %d,%d (%d loaded) ", cols, rows, drawn / (t - shown), fps, ema * 1e3, n / 1024.0,
                     ACTNAME[rav[0].act], vs.on ? vis[vs.idx].name : "-", vs.on ? (int)vs.x[0] : 0, vs.on ? (int)vs.y[0] : 0, nvis);
            shown = t; drawn = 0;
        }
        if (!fixed_fps && fps > 20) {
            slow = ema > 0.8 / fps ? slow + 1 : 0;
            if (slow > 3 * fps) { fps = fps > 48 ? 48 : fps > 40 ? 40 : fps > 30 ? 30 : fps > 24 ? 24 : 20; slow = 0; }
        }
        next += 1.0 / fps;
        double nw = now_s(); if (next < nw - 0.1) next = nw;
        if (next > nw) { struct timespec ts = { (time_t)next, (long)((next - (time_t)next) * 1e9) }; clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, 0); }
    }
    return 0;
}
