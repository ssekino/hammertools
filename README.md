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
Navigation waits for a main/focused window before opening the pane, resolves
fresh controls after tab changes, and retries an unchanged switch at most three
times. It also handles cold launches where macOS reports an empty window list.
Locked sessions defer changes. Transient navigation failures retry after 30
seconds; three failed attempts pause automation. Missing Accessibility permission
pauses immediately. Errors appear in Console and `scrollToggle.lastError`.
Run `scrollToggle.enable()` after resolving a paused error.
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


## Failure diagnostics and session tests

Navigation attempts record the pane, main/focused/window-list discovery,
control roles/identifiers/labels/enabled states, checkbox and tab values,
requested direction, process ID, and timed navigation steps. Reports stay local:

- `~/.hammerspoon/scroll-toggle-diagnostics/latest-attempt.json`: most recent attempt.
- `~/.hammerspoon/scroll-toggle-diagnostics/last-failure.json`: most recent failure,
  retained even after later success. `scrollToggle.lastDiagnostic` points here.

To capture the current pane without changing scrolling, use
`scrollToggle.captureDiagnostics("manual inspection")` in Hammerspoon Console.
Reports may contain Settings labels and account names; they are not committed or
uploaded automatically. Editable field contents are excluded.

On November 18, 2026, the previous navigator reproduced a timeout after a cold
Settings launch: its window-list/first-window assumption did not yield usable
Trackpad controls. The revised navigator passed three fresh Settings launches,
a General-to-Trackpad transition, and both natural-scrolling values. Natural
scrolling was restored on for the disconnected-mouse state. The real Bluetooth
power-off/on transitions were previously verified on November 16.

Run the isolated regression suite with Lua 5.4:

```sh
cd ~/Codex/hammertools
lua tests/scroll-toggle-test.lua
```

Or in Hammerspoon Console:

```lua
dofile(os.getenv("HOME") .. "/Codex/hammertools/tests/scroll-toggle-test.lua")
```

The suite mocks all UI, timers, process launches, and diagnostic writes; it checks
cold startup, empty window lists, nameless tabs, ignored presses, bounded retries,
failure snapshots, permission failures, locked sessions, and cancellation.
