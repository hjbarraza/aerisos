import qs.Ui

// The desktop pet's paw icon (dim while the pet is hidden). Click opens PetPopup;
// `aeris-pet` pushes a bar refresh when the pet starts or stops.
StatusModule {
    cmd: ["sh", "-c", "~/.local/bin/aeris-pet status"]
    interval: 60000
}
