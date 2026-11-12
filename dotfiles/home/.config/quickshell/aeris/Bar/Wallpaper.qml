import qs.Ui

// The 3D wallpaper icon (dim while it is off). Click opens WallpaperPopup.
StatusModule {
    cmd: ["sh", "-c", "~/.local/bin/aeris-wallpaper status"]
    interval: 60000
}
