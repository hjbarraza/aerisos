# Terminal wallpapers (Tiny Raven)

Two live wallpapers drawn in a terminal. Each frame is painted as a greyscale picture at Braille-dot
resolution (2 × 4 dots per character cell). Every cell then picks two greys and the glyph that best
splits its eight dots: a block octant where the picture is solid, a Braille pattern where it is stippled.
At a small font (5 pt) each dot is 2 × 2 screen pixels.

| Wallpaper | What it is |
|---|---|
| `murmuration/` | a flock of starlings over a moonlit sky |
| `ravenwood/` | a misty moonlit forest with one raven; visitors (owl, fox, deer…) in `visitors/` |

## Build and run

```
cc -O2 -march=native -ffast-math -o murmuration murmuration/murmuration.c -lm
cc -O2 -march=native -ffast-math -o ravenwood  ravenwood/ravenwood.c -lm
./ravenwood --fps 30
```

`ravenwood` reads `*.visitor` files from `~/.config/aeris/ravenwood/`; `ravenwood/make-visitors.py`
regenerates them. `previews/` holds one still per scene.
