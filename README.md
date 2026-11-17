# hammertools

MacBook automations using Hammerspoon.

## Repository location

Use `~/Codex/hammertools` as the persistent local repository root, including
its `.git` directory. Make project changes here rather than in a dated chat
workspace; use chat workspaces only for temporary files or deliverables.

```sh
cd ~/Codex/hammertools
```

The running Hammerspoon configuration lives separately in `~/.hammerspoon/`.
Repository edits do not automatically update those installed copies; copy the
changed configuration files there and reload Hammerspoon when deploying changes.

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
Changing direction requires Hammerspoon Accessibility access under
System Settings → Privacy & Security → Accessibility. The navigator opens the Trackpad pane,
selects Scroll & Zoom by its accessibility description, and finds the switch
by `NaturalScrollingToggle` (with an accessible-label fallback). It verifies both
the switch value and the live system scroll direction, allowing time for updates.
Navigation is bounded by a timeout; errors pause automation and appear in Console
and `scrollToggle.lastError`. Run `scrollToggle.enable()` after resolving an error.
The English tab-label fallback currently requires an English System Settings UI.

macOS exposes a system-wide natural scrolling direction. Enabling this
connection-based toggle will change trackpad direction too while a mouse is
connected. This does not provide independent simultaneous device preferences.

See `outputs/Installation-and-tests.txt` for the full activation and rollback
procedure. `hammerspoon/` is the authoritative configuration source;
`outputs/scroll-toggle.lua` is the original downloadable copy.


## Validation

On November 16, 2026, the navigation fix passed live tests on macOS 26.5.2:

- Selected Scroll & Zoom from Point & Click and toggled natural scrolling on/off.
- Magic Mouse powered off: no external mouse detected; natural scrolling on.
- Magic Mouse powered on: Bluetooth mouse detected; natural scrolling off.
- Automation remained enabled with no error after both physical transitions.

The repository configuration still defaults to preview mode. The installed local
configuration can explicitly enable automation after testing.
