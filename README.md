# hammertools

MacBook automations using Hammerspoon.

## Scroll toggle

Hammerspoon 1.x configuration. Startup is always read-only preview mode.
No startup call to `enable()` is included.

## Preview

Copy `hammerspoon/init.lua` and `hammerspoon/scroll-toggle.lua` into
`~/.hammerspoon/` (merge init.lua if you already have a configuration).
Launch Hammerspoon, reload its config, and open its Console.
The detector logs external mouse presence every time that state changes.
It polls macOS HID devices every five seconds and excludes built-in devices.

Disconnect or turn off all mice: expect `External mouse = false`.
Connect a mouse: expect `External mouse = true` with the mouse name.
Also test startup with a mouse attached, sleep/wake, and multiple mice.
A USB receiver may remain visible after its mouse is switched off.

Preview does not need Accessibility permission or alter scrolling settings.
Actual setting changes are separately gated by an explicit `enable()` call.
Do not enable until detection is tested and the user confirms activation.
The English System Settings automation for changing direction is untested.

macOS exposes a system-wide natural scrolling direction. Enabling this
connection-based toggle will change trackpad direction too while a mouse is
connected. This does not provide independent simultaneous device preferences.

See `outputs/Installation-and-tests.txt` for the full activation and rollback
procedure. `hammerspoon/` is the authoritative configuration source;
`outputs/scroll-toggle.lua` is the original downloadable copy.
