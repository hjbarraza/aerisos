import qs.Ui

// The Tailscale icon; `tailscale-status toggle` pushes a refresh after connecting or
// disconnecting. Click handlers are set by the bar (popup, admin console).
StatusModule {
    cmd: ["sh", "-c", "~/.local/bin/tailscale-status"]
    interval: 60000
}
