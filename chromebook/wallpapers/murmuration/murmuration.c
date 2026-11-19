/* murmuration: a dusk sky with a murmuration of starlings, for the terminal.
 *
 * A 3D flock (separation, alignment, cohesion, a wandering roost volume, a divergence-free
 * wind field and now and then a falcon) is projected onto the screen. Each bird is a Braille
 * dot, or a few dots of flapping wing when it is close; a bird's brightness follows how much
 * wing it shows the viewer, so a turning flock ripples the way a real one does. The moon and
 * the trees are block octants (2x4 solid pixels per cell), so birds cross the moon as
 * silhouettes. Stars are small Unicode glyphs. Everything is grey: no hue.
 *
 *   murmuration [--fps N] [--birds N] [--seed N] [--stats] [--bench FRAMES]
 *
 * Build: cc -O2 -march=native -ffast-math -o murmuration murmuration.c -lm
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


/* ---------- small helpers ---------- */
static uint32_t rng_s = 0x9e3779b9u;
static inline uint32_t rnd(void) { rng_s ^= rng_s << 13; rng_s ^= rng_s >> 17; rng_s ^= rng_s << 5; return rng_s; }
static inline float frand(void) { return (rnd() >> 8) * (1.0f / 16777216.0f); }
static inline float srand1(void) { return frand() * 2.0f - 1.0f; }
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
static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* ---------- screen ---------- */
static int cols, rows, W, H;      /* cells, and dots (2 x 4 per cell) */
static float asp = 1.0f;          /* dot width / dot height */
static float focal, horizon;      /* focal length in dots; horizon line in dots from the top */
static float *acc;                /* bird light per dot, this frame */
static uint8_t *solid;            /* per dot: 1 ground or tree, 2 moon */
static uint8_t *skybg, *cloud;    /* per cell: background grey; cloud cover 0..255 */
static uint32_t *pg; static uint8_t *pf, *pb;   /* what is on screen: glyph, fg, bg */
static char *out; static size_t outcap;
static float moonx, moony, moonr;
static char num[256][4]; static uint8_t numlen[256];

/* ---------- flock ---------- */
#define RN 7.0f                   /* neighbour radius */
#define RS 2.8f                   /* separation radius */
#define V0 14.0f                  /* cruise speed */
static int N;
static float *px, *py, *pz, *vx, *vy, *vz, *ax, *ay, *az, *bank, *flap, *flaprate, *sf, *jx, *jy, *jz;
static float *sx_, *sy_, *sz_, *svx, *svy, *svz;   /* sorted copies for the neighbour search */
static int *cellof, *cstart, *order;
#define GX 40
#define GY 20
#define GZ 40
static int gx, gy, gz; static float gox, goy, goz, gcs;
static float Tx, Ty, Tz, Rx, Ry, Rz;        /* the roost volume the flock keeps to */
static float cenx, ceny, cenz;                    /* flock centroid */
static double simt;
/* the falcon */
static int fstate; static float ftimer, fpx, fpy, fpz, fvx, fvy, fvz, fflap;

static void target_update(double t) {
    float u = 0.36f * sinf(0.071f * t + 1.0f) + 0.17f * sinf(0.173f * t + 2.3f) + 0.05f * sinf(0.41f * t);
    float w = 0.50f + 0.13f * sinf(0.093f * t + 0.4f) + 0.07f * sinf(0.21f * t + 1.0f);
    Tz = 96.0f + 20.0f * sinf(0.057f * t + 0.5f) + 9.0f * sinf(0.131f * t);
    Tx = u * Tz * (W * 0.5f) / focal;
    Ty = w * horizon / (focal * asp) * Tz;
    float s = cbrtf(N / 2600.0f);
    Rx = s * 34.0f; Ry = s * 9.0f; Rz = s * 24.0f;      /* only used to scatter the birds at the start */
}

static void flock_init(int n) {
    N = n;
    float **arrs[] = { &px, &py, &pz, &vx, &vy, &vz, &ax, &ay, &az, &bank, &flap, &flaprate, &sf, &jx, &jy, &jz,
                       &sx_, &sy_, &sz_, &svx, &svy, &svz };
    for (unsigned i = 0; i < sizeof arrs / sizeof *arrs; i++) *arrs[i] = calloc(N, sizeof(float));
    cellof = calloc(N, sizeof(int)); order = calloc(N, sizeof(int));
    cstart = calloc(GX * GY * GZ + 1, sizeof(int));
    target_update(0);
    /* one main body and two smaller groups arriving from the sides */
    for (int i = 0; i < N; i++) {
        int g = i < N * 0.62f ? 0 : i < N * 0.84f ? 1 : 2;
        float ox = g == 0 ? 0 : g == 1 ? -60 : 62, oy = g == 2 ? 8 : -4, oz = g == 1 ? 25 : -12;
        float r = cbrtf(frand()), th = frand() * 6.2832f, ph = acosf(srand1());
        float k = g == 0 ? 1.0f : 0.5f;
        px[i] = Tx + ox + k * Rx * r * sinf(ph) * cosf(th);
        py[i] = Ty + oy + k * Ry * r * cosf(ph);
        pz[i] = Tz + oz + k * Rz * r * sinf(ph) * sinf(th);
        float dir = g == 1 ? 1 : g == 2 ? -1 : 0.6f;
        vx[i] = V0 * dir + srand1() * 2; vy[i] = srand1(); vz[i] = srand1() * 3 + (g == 0 ? 6 : 0);
        sf[i] = 1.0f + 0.13f * srand1(); flap[i] = frand() * 6.2832f; flaprate[i] = 26.0f + 10.0f * frand();
    }
    fstate = 0; ftimer = 22.0f + 10.0f * frand();
}

static void grid_build(void) {
    float mnx = 1e9f, mny = 1e9f, mnz = 1e9f, mxx = -1e9f, mxy = -1e9f, mxz = -1e9f;
    double sx = 0, sy = 0, sz = 0;
    for (int i = 0; i < N; i++) {
        if (px[i] < mnx) mnx = px[i]; if (px[i] > mxx) mxx = px[i];
        if (py[i] < mny) mny = py[i]; if (py[i] > mxy) mxy = py[i];
        if (pz[i] < mnz) mnz = pz[i]; if (pz[i] > mxz) mxz = pz[i];
        sx += px[i]; sy += py[i]; sz += pz[i];
    }
    cenx = sx / N; ceny = sy / N; cenz = sz / N;
    gcs = RN;
    if ((mxx - mnx) / GX > gcs) gcs = (mxx - mnx) / GX;
    if ((mxy - mny) / GY > gcs) gcs = (mxy - mny) / GY;
    if ((mxz - mnz) / GZ > gcs) gcs = (mxz - mnz) / GZ;
    gcs *= 1.001f;
    gox = mnx; goy = mny; goz = mnz;
    gx = (int)((mxx - mnx) / gcs) + 1; gy = (int)((mxy - mny) / gcs) + 1; gz = (int)((mxz - mnz) / gcs) + 1;
    if (gx > GX) gx = GX; if (gy > GY) gy = GY; if (gz > GZ) gz = GZ;
    int nc = gx * gy * gz;
    memset(cstart, 0, (nc + 1) * sizeof(int));
    float inv = 1.0f / gcs;
    for (int i = 0; i < N; i++) {
        int ix = (int)((px[i] - gox) * inv), iy = (int)((py[i] - goy) * inv), iz = (int)((pz[i] - goz) * inv);
        if (ix >= gx) ix = gx - 1; if (iy >= gy) iy = gy - 1; if (iz >= gz) iz = gz - 1;
        int c = ix + gx * (iy + gy * iz);
        cellof[i] = c; cstart[c + 1]++;
    }
    for (int c = 0; c < nc; c++) cstart[c + 1] += cstart[c];
    for (int i = N - 1; i >= 0; i--) order[--cstart[cellof[i] + 1]] = i;
    /* cstart[c+1] now holds the start of cell c; shift so cstart[c] does */
    for (int c = 0; c < nc; c++) cstart[c] = cstart[c + 1];
    cstart[nc] = N;
    for (int k = 0; k < N; k++) {
        int i = order[k];
        sx_[k] = px[i]; sy_[k] = py[i]; sz_[k] = pz[i]; svx[k] = vx[i]; svy[k] = vy[i]; svz[k] = vz[i];
    }
}

static void falcon_step(float dt) {
    ftimer -= dt;
    if (fstate == 0) {
        if (ftimer <= 0) {            /* stoop on the flock from above and to one side */
            float side = frand() < 0.5f ? -1 : 1;
            fpx = cenx + side * (70 + 30 * frand()); fpy = ceny + 30 + 15 * frand(); fpz = cenz + srand1() * 40;
            float dx = cenx - fpx, dy = ceny - fpy, dz = cenz - fpz, d = sqrtf(dx * dx + dy * dy + dz * dz);
            fvx = dx / d * 30; fvy = dy / d * 30; fvz = dz / d * 30;
            fstate = 1; ftimer = 9.0f + 4.0f * frand();
        }
        return;
    }
    float tx, ty, tz;
    if (fstate == 1) { tx = cenx - fpx; ty = ceny - fpy; tz = cenz - fpz; }
    else { tx = fvx; ty = fabsf(fvy) + 12; tz = fvz + 10; }
    float d = sqrtf(tx * tx + ty * ty + tz * tz) + 1e-3f;
    float sp = fstate == 1 ? 31.0f : 24.0f, k = fstate == 1 ? 1.5f : 0.8f;
    fvx += (tx / d * sp - fvx) * k * dt; fvy += (ty / d * sp - fvy) * k * dt; fvz += (tz / d * sp - fvz) * k * dt;
    fpx += fvx * dt; fpy += fvy * dt; fpz += fvz * dt;
    fflap += dt * 9.0f;
    if (fpz < 12) fpz = 12;
    if (ftimer <= 0) {
        if (fstate == 1) { fstate = 2; ftimer = 9.0f; }
        else { fstate = 0; ftimer = 28.0f + 40.0f * frand(); }
    }
}

/* steering for birds whose index has the given parity (or all, if parity < 0) */
static void steer(int parity) {
    const float rn2 = RN * RN, inv = 1.0f / gcs;
    const float t = (float)simt;
    const int falcon = fstate != 0;
    const float xlim = W * 0.5f / focal, ylim = horizon / (focal * asp);
    static int nonce; nonce++;
    for (int k = 0; k < N; k++) {
        int i = order[k];
        if (parity >= 0 && i % 3 != parity) continue;
        float x = sx_[k], y = sy_[k], z = sz_[k], ux = svx[k], uy = svy[k], uz = svz[k];
        int c = cellof[i];
        int ix = c % gx, iy = (c / gx) % gy, iz = c / (gx * gy);
        (void)inv;
        float sepx = 0, sepy = 0, sepz = 0, avx = 0, avy = 0, avz = 0, cx = 0, cy = 0, cz = 0, wsum = 0;
        int z0 = iz > 0 ? iz - 1 : 0, z1 = iz < gz - 1 ? iz + 1 : gz - 1;
        int y0 = iy > 0 ? iy - 1 : 0, y1 = iy < gy - 1 ? iy + 1 : gy - 1;
        int x0 = ix > 0 ? ix - 1 : 0, x1 = ix < gx - 1 ? ix + 1 : gx - 1;
        for (int zz = z0; zz <= z1; zz++)
            for (int yy = y0; yy <= y1; yy++) {
                int base = gx * (yy + gy * zz);
                int a = cstart[base + x0], b = cstart[base + x1 + 1];
                for (int j = a; j < b; j++) {
                    float dx = sx_[j] - x, dy = sy_[j] - y, dz = sz_[j] - z;
                    float d2 = dx * dx + dy * dy + dz * dz;
                    if (d2 >= rn2 || d2 < 1e-8f) continue;
                    float w = 1.0f - d2 / rn2;
                    avx += svx[j] * w; avy += svy[j] * w; avz += svz[j] * w;
                    cx += dx * w; cy += dy * w; cz += dz * w; wsum += w;
                    if (d2 < RS * RS) {
                        float d = sqrtf(d2), s = (1.0f - d / RS) / d;
                        sepx -= dx * s; sepy -= dy * s; sepz -= dz * s;
                    }
                }
            }
        float fx = 0, fy = 0, fz = 0;
        if (wsum > 0) {
            float iw = 1.0f / wsum;
            fx += 1.5f * (avx * iw - ux) + 0.80f * cx * iw;
            fy += 1.5f * (avy * iw - uy) + 0.80f * cy * iw;
            fz += 1.5f * (avz * iw - uz) + 0.80f * cz * iw;
        }
        fx += 13.0f * sepx; fy += 13.0f * sepy; fz += 13.0f * sepz;
        /* the roost pulls like a soft spring, so the flock swings over it and back; the
           edges of the view push back harder */
        {
            float dx = x - Tx, dy = y - Ty, dz = z - Tz;
            fx -= 0.10f * dx; fy -= 0.34f * dy; fz -= 0.22f * dz;
            float xl = 0.86f * z * xlim, yl = 0.90f * z * ylim;
            if (x > xl) fx -= (x - xl) * 1.6f; else if (x < -xl) fx -= (x + xl) * 1.6f;
            if (y > yl) fy -= (y - yl) * 2.5f;
            if (z > 135.0f) fz -= (z - 135.0f) * 1.2f;
        }
        /* each bird also has a mind of its own: this keeps the flock from freezing into a lattice */
        {
            uint32_t h = hash2(i, nonce);
            jx[i] = 0.86f * jx[i] + ((int)(h & 1023) - 512) * (1.0f / 512.0f);
            jy[i] = 0.86f * jy[i] + ((int)(h >> 10 & 1023) - 512) * (1.0f / 512.0f);
            jz[i] = 0.86f * jz[i] + ((int)(h >> 20 & 1023) - 512) * (1.0f / 512.0f);
            fx += 2.3f * jx[i]; fy += 1.2f * jy[i]; fz += 2.3f * jz[i];
        }
        /* wind: each component ignores its own axis, so the field has no sources or sinks */
        fx += 4.6f * (sinf(0.105f * y + 0.33f * t) + sinf(0.071f * z - 0.26f * t + 1.3f));
        fy += 2.2f * (sinf(0.083f * z + 0.29f * t) + sinf(0.067f * x - 0.21f * t + 2.1f));
        fz += 4.6f * (sinf(0.077f * x + 0.31f * t) + sinf(0.110f * y - 0.24f * t + 4.2f));
        /* stay above the trees, fly mostly level */
        fy -= 0.9f * uy;
        if (y < 7.0f) fy += (7.0f - y) * 6.0f;
        if (z < 48.0f) fz += (48.0f - z) * 1.5f;
        float fear = 0;
        if (falcon) {
            float dx = x - fpx, dy = y - fpy, dz = z - fpz, d2 = dx * dx + dy * dy + dz * dz;
            const float rp = 24.0f;
            if (d2 < rp * rp) {
                float d = sqrtf(d2) + 1e-3f; fear = 1.0f - d / rp;
                float s = 150.0f * fear * fear / d;
                fx += dx * s; fy += dy * s * 0.6f; fz += dz * s;
            }
        }
        /* hold cruise speed (faster when frightened) */
        float sp = sqrtf(ux * ux + uy * uy + uz * uz) + 1e-4f;
        float want = V0 * sf[i] * (1.0f + 0.55f * fear);
        float s = 2.2f * (want - sp) / sp;
        fx += ux * s; fy += uy * s; fz += uz * s;
        float a2 = fx * fx + fy * fy + fz * fz;
        const float amax = 46.0f + 60.0f * fear;
        if (a2 > amax * amax) { float q = amax / sqrtf(a2); fx *= q; fy *= q; fz *= q; }
        ax[i] = fx; ay[i] = fy; az[i] = fz;
    }
}

static void integrate(float dt) {
    for (int i = 0; i < N; i++) {
        float ux = vx[i], uz = vz[i];
        /* bank into the turn: sideways pull over gravity */
        float h = sqrtf(ux * ux + uz * uz) + 1e-4f;
        float lat = (ax[i] * -uz + az[i] * ux) / h;      /* along right = v x up, flattened */
        float want = atanf(lat * (1.0f / 9.0f));
        bank[i] += (want - bank[i]) * fminf(1.0f, 7.0f * dt);
        vx[i] += ax[i] * dt; vy[i] += ay[i] * dt; vz[i] += az[i] * dt;
        float sp2 = vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i];
        if (sp2 > 26.0f * 26.0f) { float q = 26.0f / sqrtf(sp2); vx[i] *= q; vy[i] *= q; vz[i] *= q; }
        else if (sp2 < 64.0f) { float q = 8.0f / (sqrtf(sp2) + 1e-4f); vx[i] *= q; vy[i] *= q; vz[i] *= q; }
        px[i] += vx[i] * dt; py[i] += vy[i] * dt; pz[i] += vz[i] * dt;
        flap[i] += flaprate[i] * dt;
    }
}

/* ---------- scenery ---------- */
static void setsolid(int x, int y, uint8_t v) { if (x >= 0 && x < W && y >= 0 && y < H) solid[y * W + x] = v; }
/* Trees are kept as a hierarchy of branches so the wind can move them: every branch turns a
   little at its joint, twigs more and faster than limbs, and the turns add up toward the tips. */
typedef struct { int parent, level, steps; float rel, len, bend, thick, phase, rootx, rooty; } Branch;
#define MAXBR 6000
static Branch br[MAXBR]; static float bex[MAXBR], bey[MAXBR], bea[MAXBR]; static int nbr;
static uint8_t *solid0; static float *ground;

static void grow(int parent, float rel, float len, int depth, float thick, int level, float absang, float rx, float ry) {
    if (nbr >= MAXBR) return;
    int id = nbr++;
    Branch *b = &br[id];
    b->parent = parent; b->level = level; b->rel = rel; b->len = len; b->thick = thick;
    b->steps = (int)(len * 1.5f) + 1; b->bend = srand1() * 0.25f / b->steps; b->phase = frand() * 6.2832f;
    b->rootx = rx; b->rooty = ry;
    float endang = absang + b->bend * b->steps;
    if (depth <= 0 || len < 1.2f) return;
    int kids = depth > 3 ? 2 + (rnd() % 2) : 2 + (rnd() % 3 == 0);
    for (int k = 0; k < kids; k++) {
        float spread = 0.30f + 0.45f * frand();
        float a = endang + (k == 0 ? -spread : k == 1 ? spread : srand1() * 0.25f);
        a *= 0.93f;                                   /* reach for the light */
        grow(id, a - endang, len * (0.62f + 0.2f * frand()), depth - 1, thick - 1, level + 1, a, 0, 0);
    }
}
static void tree(float x, float y, float ang, float len, int depth, float thick) { grow(-1, ang, len, depth, thick, 0, ang, x, y); }

/* the breeze at a place and time: 0 nearly still .. 1 a gust; it travels right to left like the clouds */
static inline float breeze(float t, float x) {
    float g = 0.50f + 0.30f * sinf(0.19f * t + x * 0.012f) + 0.20f * sinf(0.47f * t + x * 0.021f + 1.7f);
    return g * (0.65f + 0.35f * sinf(0.043f * t + 0.6f));
}

static void trees_draw(float t) {
    memcpy(solid, solid0, (size_t)W * H);
    for (int x = 0; x < W; x++) {                    /* the far treeline stirs by a dot or so */
        float gst = breeze(t, x);
        int top = (int)(ground[x] - 0.9f * gst * (0.5f + 0.5f * sinf(x * 0.41f + t * 1.3f)) * vnoise(x * 0.9f, 5.0f) * 2.0f);
        for (int y = top < 0 ? 0 : top; y < H && !solid[y * W + x]; y++) solid[y * W + x] = 1;
    }
    for (int i = 0; i < nbr; i++) {
        Branch *b = &br[i];
        float x, y, ang;
        if (b->parent < 0) { x = b->rootx; y = b->rooty; ang = b->rel; }
        else { x = bex[b->parent]; y = bey[b->parent]; ang = bea[b->parent] + b->rel; }
        float g = breeze(t, x), L = b->level;
        ang += -g * 0.0045f * (L + 1.0f)                                       /* leaning downwind */
             + g * (0.007f + 0.005f * L) * sinf((1.5f + 0.55f * L) * t + b->phase + x * 0.02f);
        if (b->level >= 3) ang += g * 0.016f * sinf((5.5f + L) * t + b->phase * 5.0f);   /* twigs flutter */
        float step = b->len / b->steps;
        for (int s = 0; s < b->steps; s++) {
            int xi = (int)lroundf(x), yi = (int)lroundf(y);
            setsolid(xi, yi, 1);
            if (b->thick >= 2) setsolid(xi + 1, yi, 1);
            if (b->thick >= 3) setsolid(xi - 1, yi, 1);
            x += sinf(ang) * step; y -= cosf(ang) * step * asp;
            ang += b->bend;
        }
        bex[i] = x; bey[i] = y; bea[i] = ang;
    }
}

static void scenery_build(void) {
    uint32_t keep = rng_s; rng_s = 0x51ab37u;        /* the same landscape every time */
    memset(solid0, 0, (size_t)W * H);
    for (int x = 0; x < W; x++)                      /* far treeline over low hills */
        ground[x] = horizon - (1.5f + H * 0.035f * fbm(x * 0.018f, 3.0f) + H * 0.02f * fbm(x * 0.21f, 9.0f)
                               + 1.2f * vnoise(x * 0.9f, 5.0f));
    /* two near trees frame the sky, a few small ones stand on the line */
    nbr = 0;
    tree(W * 0.075f, horizon + 1, -0.05f, H * 0.105f, 7, 3);
    tree(W * 0.925f, horizon + 1, 0.08f, H * 0.085f, 6, 3);
    tree(W * 0.30f, horizon - 1, 0.03f, H * 0.04f, 4, 1);
    tree(W * 0.58f, horizon - 1, -0.04f, H * 0.055f, 5, 1);
    tree(W * 0.70f, horizon - 1, 0.05f, H * 0.035f, 4, 1);
    /* the moon */
    moonx = W * 0.79f; moony = H * 0.19f; moonr = fmaxf(4.5f, H * 0.048f);
    for (int y = (int)(moony - moonr - 2); y <= (int)(moony + moonr + 2); y++)
        for (int x = (int)(moonx - moonr - 2); x <= (int)(moonx + moonr + 2); x++) {
            float dx = x + 0.5f - moonx, dy = (y + 0.5f - moony) / asp;
            if (dx * dx + dy * dy < moonr * moonr && x >= 0 && x < W && y >= 0 && y < H) solid0[y * W + x] = 2;
        }
    rng_s = keep;
    trees_draw(0);
}

static void sky_update(double t) {
    float sunx = cols * 0.27f;
    /* how much cloud there is drifts too: clear spells, then a bank passes */
    float cover = 0.50f + 0.11f * sinf(0.017f * (float)t + 2.0f) + 0.05f * sinf(0.051f * (float)t);
    for (int r = 0; r < rows; r++) {
        float yd = r * 4 + 2.0f, tf = clampf(yd / horizon, 0, 1);
        for (int c = 0; c < cols; c++) {
            float g = 5.0f + 52.0f * powf(tf, 2.4f);
            float dxs = (c - sunx) / (cols * 0.33f);
            g += 40.0f * expf(-dxs * dxs) * powf(tf, 3.2f);              /* where the sun went down */
            float n = fbm(c * 0.016f + (float)t * 0.013f, r * 0.075f + (float)t * 0.0015f);
            float n2 = fbm(c * 0.035f + (float)t * 0.041f + 40.0f, r * 0.2f + 11.0f);
            float cl = smooth(cover, cover + 0.36f, n * 0.85f + n2 * 0.2f);
            cl *= smooth(0.03f, 0.3f, tf) ;
            g += cl * (13.0f + 24.0f * tf * tf + 22.0f * expf(-dxs * dxs) * tf);
            float mx = (c * 2 + 1 - moonx), my = (yd - moony) / asp, md2 = mx * mx + my * my;
            g += (16.0f + 38.0f * cl) * expf(-md2 / (moonr * moonr * 16.0f));
            if (yd > horizon) g = 0;
            skybg[r * cols + c] = (uint8_t)clampf(g, 0, 255);
            cloud[r * cols + c] = (uint8_t)(cl * 255);
        }
    }
}

/* ---------- drawing ---------- */
static inline void dot(float x, float y, float v) {
    int xi = (int)floorf(x), yi = (int)floorf(y);
    if (xi >= 0 && xi < W && yi >= 0 && yi < H) acc[yi * W + xi] += v;
}

/* a bird big enough to have wings: body along its heading, wings across, tips beating */
static void wings(float sx, float sy, float span, float hx, float hy, float wx, float wy, float beat, float v) {
    float half = span * 0.5f;
    dot(sx, sy, v);
    if (span > 2.6f) dot(sx + hx * half * 0.7f, sy + hy * half * 0.7f, v * 0.9f);
    int n = (int)ceilf(half);
    for (int k = 1; k <= n; k++) {
        float f = (float)k / n, lift = -beat * f * f * half * 0.9f;
        float fore = fabsf(beat) * 0.15f;             /* wings shorten as they swing */
        float ex = wx * half * f * (1.0f - fore), ey = wy * half * f * (1.0f - fore);
        dot(sx + ex, sy + ey + lift, v * (1.0f - 0.25f * f));
        dot(sx - ex, sy - ey + lift, v * (1.0f - 0.25f * f));
    }
}

static void draw_birds(void) {
    memset(acc, 0, (size_t)W * H * sizeof(float));
    const float cx = W * 0.5f, fa = focal * asp;
    for (int i = 0; i < N; i++) {
        float z = pz[i];
        if (z < 6.0f) continue;
        float iz = 1.0f / z;
        float sx = cx + px[i] * iz * focal, sy = horizon - py[i] * iz * fa;
        if (sx < -4 || sx >= W + 4 || sy < -4 || sy >= H + 4) continue;
        float ux = vx[i], uy = vy[i], uz = vz[i];
        float sp = sqrtf(ux * ux + uy * uy + uz * uz) + 1e-4f;
        ux /= sp; uy /= sp; uz /= sp;
        /* right = heading x up; wing normal leans from up toward right by the bank angle */
        float h = sqrtf(ux * ux + uz * uz) + 1e-4f;
        float rx = -uz / h, rz = ux / h;
        float cb = cosf(bank[i]), sb = sinf(bank[i]);
        float nx = rx * sb - uy * ux / h * cb, ny = h * cb, nz = rz * sb - uy * uz / h * cb;
        float d = sqrtf(px[i] * px[i] + py[i] * py[i] + z * z);
        float show = fabsf(nx * px[i] + ny * py[i] + nz * z) / d;        /* wing area facing us */
        float beat = sinf(flap[i]);
        float v = clampf(1.38f - z * (1.0f / 150.0f), 0.40f, 1.25f) * (0.30f + 1.5f * show) * (0.9f + 0.1f * beat);
        float span = focal * 0.34f * iz;
        if (span < 1.7f) { dot(sx, sy, v); continue; }
        /* wing axis on screen: right * cos(bank) + up' * sin(bank), projected */
        float wxw = rx * cb + (-uy * ux / h) * sb, wyw = h * sb, wzw = rz * cb;
        (void)wzw;
        wings(sx, sy, span, ux, -uy * asp, wxw, -wyw * asp, beat, v);
    }
    if (fstate != 0 && fpz > 8.0f) {
        float iz = 1.0f / fpz, sx = cx + fpx * iz * focal, sy = horizon - fpy * iz * fa;
        float sp = sqrtf(fvx * fvx + fvy * fvy + fvz * fvz) + 1e-4f;
        float ux = fvx / sp, uy = fvy / sp, uz = fvz / sp, h = sqrtf(ux * ux + uz * uz) + 1e-4f;
        float span = fmaxf(3.0f, focal * 1.9f * iz);
        float beat = fstate == 1 ? 0.25f * sinf(fflap) - 0.35f : sinf(fflap);   /* wings tucked in the stoop */
        wings(sx, sy, span, ux, -uy * asp, -uz / h + 0.35f * ux, 0.0f, beat, 1.6f);
        dot(sx - ux * 1.2f, sy + uy * asp * 1.2f, 1.2f);
    }
}

static inline char *put_utf8(char *o, uint32_t c) {
    if (c < 0x80) *o++ = c;
    else if (c < 0x800) { *o++ = 0xC0 | (c >> 6); *o++ = 0x80 | (c & 0x3F); }
    else if (c < 0x10000) { *o++ = 0xE0 | (c >> 12); *o++ = 0x80 | ((c >> 6) & 0x3F); *o++ = 0x80 | (c & 0x3F); }
    else { *o++ = 0xF0 | (c >> 18); *o++ = 0x80 | ((c >> 12) & 0x3F); *o++ = 0x80 | ((c >> 6) & 0x3F); *o++ = 0x80 | (c & 0x3F); }
    return o;
}
static inline char *put_num(char *o, int v) { memcpy(o, num[v], 4); return o + numlen[v]; }

static const uint32_t STARS[] = { 0xB7, 0x2D9, 0x22C5, 0x2219, 0xB7, 0x2D9, 0x22C6, 0x2726, 0x2B, 0x2D6, 0xB7, 0x2027 };
static uint8_t BRAILLE[256];
static char statline[96];

static size_t compose(double t, int full) {
    char *o = out;
    memcpy(o, "\x1b[?2026h", 8); o += 8;
    int curfg = -1, curbg = -1, cr = -1, cc = -1;
    int slen = (int)strlen(statline);
    for (int r = 0; r < rows; r++) {
        const float *a0 = acc + (size_t)(r * 4) * W;
        const uint8_t *s0 = solid + (size_t)(r * 4) * W;
        for (int c = 0; c < cols; c++) {
            int idx = r * cols + c;
            unsigned bm = 0, gm = 0, mm = 0; float sum = 0;
            for (int yy = 0; yy < 4; yy++) {
                const float *a = a0 + yy * W + c * 2; const uint8_t *s = s0 + yy * W + c * 2;
                if (a[0] > 0) { bm |= 1u << (yy * 2); sum += a[0]; }
                if (a[1] > 0) { bm |= 2u << (yy * 2); sum += a[1]; }
                if (s[0] == 1) gm |= 1u << (yy * 2); else if (s[0] == 2) mm |= 1u << (yy * 2);
                if (s[1] == 1) gm |= 2u << (yy * 2); else if (s[1] == 2) mm |= 2u << (yy * 2);
            }
            uint32_t g = ' '; int fg = 0, bg = skybg[idx];
            int kind = 0;   /* 0 sky or star, 1 status, 2 ground, 3 moon, 4 birds */
            if (r == 0 && c < slen) { g = statline[c]; fg = 200; bg = 0; kind = 1; }
            else if (gm == 255) { bg = 0; kind = 2; }
            else if (gm) { g = OCT[gm]; fg = 0; kind = 2; }
            else if (mm) {
                kind = 3;
                unsigned m = mm & ~bm;                      /* birds cross the moon as shadows */
                if (m) {
                    g = OCT[m];
                    fg = 236 - (cloud[idx] * 5 >> 4);
                    fg &= ~3;
                }
            } else if (bm) {
                kind = 4;
                int pop = __builtin_popcount(bm);
                float m = sum / pop;
                float L = 1.0f - expf(-1.3f * m - 0.07f * pop);
                fg = bg + 108 + (int)((255 - bg - 108) * L);
                fg -= fg * cloud[idx] >> 11;
                fg = (fg + 3) & ~7; if (fg > 255) fg = 255;
                g = 0x2800 + BRAILLE[bm];
            } else {
                uint32_t h = hash2(c * 7 + 13, r * 13 + 5);
                float up = 1.0f - (r * 4 + 2) / horizon;     /* more stars higher up */
                if ((h & 1023) < (uint32_t)(34.0f * up * up + 2.0f) && cloud[idx] < 90 && up > 0.12f) {
                    float ph = (h >> 10 & 255) * 0.0245f, sp = 0.5f + (h >> 18 & 15) * 0.16f;
                    float tw = 0.62f + 0.38f * sinf((float)t * sp + ph) * sinf((float)t * sp * 0.37f + ph * 3);
                    int base = 70 + (h >> 22 & 127);
                    fg = bg + (int)(base * tw * (1.0f - cloud[idx] / 110.0f));
                    fg = (fg + 4) & ~7; if (fg > 255) fg = 255;
                    g = STARS[(h >> 12) % 12];
                    if (base < 150 && g > 0x2700) g = 0xB7;   /* the bright few get the big glyphs */
                }
            }
            if (light) {
                /* Day: a pale sky (brighter towards the horizon), no stars,
                 * starlings as dark specks, a faint moon, trees and ground ink. */
                int sky = 222 + bg * 33 / 90; if (sky > 255) sky = 255;
                if (kind == 0) { bg = sky; g = ' '; }
                else if (kind == 1) { bg = 255; fg = 60; }
                else if (kind == 2) { if (gm != 255) bg = sky; fg = 0; }
                else if (kind == 3) { bg = sky; fg = sky - 22; }
                else { int dark = (fg - skybg[idx]) ; if (dark < 0) dark = 0; bg = sky; fg = sky - 70 - dark * 2 / 3; if (fg < 0) fg = 0; }
            }
            if (g == ' ') fg = 0;
            if (!full && pg[idx] == g && pf[idx] == fg && pb[idx] == bg) continue;
            pg[idx] = g; pf[idx] = fg; pb[idx] = bg;
            if (cr != r || cc != c) {
                *o++ = 0x1b; *o++ = '['; o = put_num(o, (r + 1) & 255);
                *o++ = ';';
                if (c + 1 > 255) { o += sprintf(o, "%d", c + 1); } else o = put_num(o, c + 1);
                *o++ = 'H';
            }
            if (bg != curbg) {
                memcpy(o, "\x1b[48;2;", 7); o += 7; o = put_rgb(o, bg); *o++ = 'm'; curbg = bg;
            }
            if (g != ' ' && fg != curfg) {
                memcpy(o, "\x1b[38;2;", 7); o += 7; o = put_rgb(o, fg); *o++ = 'm'; curfg = fg;
            }
            o = put_utf8(o, g);
            cr = r; cc = c + 1;
        }
    }
    memcpy(o, "\x1b[?2026l", 8); o += 8;
    return o - out;
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
        if (ws.ws_xpixel > 0 && ws.ws_ypixel > 0)
            asp = ((float)ws.ws_xpixel / cols / 2.0f) / ((float)ws.ws_ypixel / rows / 4.0f);
    }
    if (cols < 20) cols = 20; if (rows < 8) rows = 8;
    if (rows > 255) rows = 255;
    W = cols * 2; H = rows * 4;
    /* a 62 degree view; the camera stands on the ground and looks up a little */
    focal = W * 0.5f / tanf(31.0f * 3.14159265f / 180.0f);
    horizon = floorf(H * 0.955f);
    free(acc); free(solid); free(solid0); free(ground); free(skybg); free(cloud); free(pg); free(pf); free(pb); free(out);
    acc = calloc((size_t)W * H, sizeof(float)); solid = calloc((size_t)W * H, 1); solid0 = calloc((size_t)W * H, 1); ground = calloc(W, sizeof(float));
    skybg = calloc(cols * rows, 1); cloud = calloc(cols * rows, 1);
    pg = calloc(cols * rows, sizeof(uint32_t)); pf = calloc(cols * rows, 1); pb = calloc(cols * rows, 1);
    outcap = (size_t)cols * rows * 56 + 64; out = malloc(outcap);
    scenery_build();
}

static void write_all(const char *b, size_t n) {
    while (n > 0 && !quit) {
        ssize_t k = write(1, b, n);
        if (k < 0) { if (quit) return; continue; }
        b += k; n -= k;
    }
}

static double skyoff; static int skyset;   /* where the sky's clock starts: the weather differs per run */

int main(int argc, char **argv) {
    int fps = 60, birds = 0, stats = 0, bench = 0, fixed_fps = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--fps") && i + 1 < argc) { fps = atoi(argv[++i]); fixed_fps = 1; }
        else if (!strcmp(argv[i], "--birds") && i + 1 < argc) birds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--seed") && i + 1 < argc) rng_s = (uint32_t)atoi(argv[++i]) * 2654435761u + 1;
        else if (!strcmp(argv[i], "--stats")) stats = 1;
        else if (!strcmp(argv[i], "--light")) { light = 1; light_table(0); }
        else if (!strcmp(argv[i], "--sky") && i + 1 < argc) { skyoff = atof(argv[++i]); skyset = 1; }
        else if (!strcmp(argv[i], "--bench") && i + 1 < argc) bench = atoi(argv[++i]);
        else {
            fprintf(stderr, "murmuration: a dusk sky with a murmuration of starlings\n"
                            "usage: murmuration [--fps N] [--birds N] [--seed N] [--sky SECONDS] [--stats] [--bench FRAMES]\n");
            return 2;
        }
    }
    if (fps < 5) fps = 5; if (fps > 120) fps = 120;
    for (int i = 0; i < 256; i++) numlen[i] = (uint8_t)sprintf(num[i], "%d", i);
    for (int m = 0; m < 256; m++) {          /* our bit y*2+x -> Braille dot bit */
        static const uint8_t map[8] = { 0x01, 0x08, 0x02, 0x10, 0x04, 0x20, 0x40, 0x80 };
        uint8_t b = 0; for (int k = 0; k < 8; k++) if (m >> k & 1) b |= map[k];
        BRAILLE[m] = b;
    }
    if (!argv[0]) return 2;
    if (!bench) {
        if (rng_s == 0x9e3779b9u) rng_s ^= (uint32_t)time(NULL) * 2246822519u;
        struct sigaction sa = { 0 }; sa.sa_handler = on_sig;
        sigaction(SIGINT, &sa, 0); sigaction(SIGTERM, &sa, 0); sigaction(SIGHUP, &sa, 0);
        sigaction(SIGWINCH, &sa, 0); sigaction(SIGCONT, &sa, 0);
        if (tcgetattr(0, &old_tio) == 0) {
            struct termios t = old_tio; t.c_lflag &= ~(ECHO | ICANON); tcsetattr(0, TCSANOW, &t); tio_saved = 1;
        }
        static const char s[] = "\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[2J";
        write_all(s, sizeof s - 1);
        atexit(term_restore);
    }
    resize(bench ? 168 : 0, bench ? 44 : 0); resized = 0;
    if (birds <= 0) birds = (int)(cols * rows * 0.36f);
    if (birds < 200) birds = 200; if (birds > 20000) birds = 20000;
    flock_init(birds);
    if (!skyset) skyoff = rnd() % 3600;

    if (bench) {
        double t0 = now_s(), ts = 0, tr = 0; size_t bytes = 0;
        for (int f = 0; f < bench; f++) {
            double a = now_s();
            simt += 1.0 / 60; target_update(simt); grid_build(); falcon_step(1.0f / 60); steer(f % 3); integrate(1.0f / 60);
            double b = now_s();
            if (f % 6 == 0) sky_update(simt);
            if (f % 2 == 0) trees_draw((float)simt);
            draw_birds(); bytes += compose(simt, 0);
            double c = now_s(); ts += b - a; tr += c - b;
        }
        printf("%d birds, %dx%d cells: sim %.2f ms, draw %.2f ms, %.1f kB/frame, total %.2f ms/frame\n", N, cols, rows,
               ts / bench * 1e3, tr / bench * 1e3, bytes / 1024.0 / bench, (now_s() - t0) / bench * 1e3);
        return 0;
    }

    double last = now_s(), next = last, ema = 0, shown = last; int frame = 0, slow = 0, full = 1, drawn = 0;
    while (!quit) {
        double t = now_s();
        float dt = (float)(t - last); last = t;
        if (woke) { woke = 0; full = 1; dt = 0; next = t; }
        if (dt > 0.05f) dt = 0.05f;                 /* after a pause, carry on rather than leap */
        if (resized) { resized = 0; resize(0, 0); full = 1; write_all("\x1b[2J", 4); }
        simt += dt;
        target_update(simt);
        grid_build();
        falcon_step(dt);
        steer(fps > 40 ? frame % 3 : -1);
        integrate(dt);
        if (full || frame % 6 == 0) sky_update(simt + skyoff);
        if (full || frame % 2 == 0) trees_draw((float)(simt + skyoff));
        draw_birds();
        size_t n = compose(simt + skyoff, full); full = 0;
        write_all(out, n);
        double work = now_s() - t;
        ema += (work - ema) * 0.05; frame++; drawn++;
        if (stats && t - shown >= 0.5) {
            snprintf(statline, sizeof statline, " %d birds %dx%d a%.2f  %4.1f fps (target %d)  work %4.1f ms  %4.1f kB ",
                     N, cols, rows, asp, drawn / (t - shown), fps, ema * 1e3, n / 1024.0);
            shown = t; drawn = 0;
        }
        /* if this machine cannot keep the pace, step down rather than stutter */
        if (!fixed_fps && fps > 24) {
            slow = ema > 0.8 / fps ? slow + 1 : 0;
            if (slow > 3 * fps) { fps = fps > 48 ? 48 : fps > 40 ? 40 : fps > 30 ? 30 : 24; slow = 0; }
        }
        next += 1.0 / fps;
        double nw = now_s();
        if (next < nw - 0.1) next = nw;
        if (next > nw) {
            struct timespec ts = { (time_t)next, (long)((next - (time_t)next) * 1e9) };
            clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, 0);
        }
    }
    return 0;
}
