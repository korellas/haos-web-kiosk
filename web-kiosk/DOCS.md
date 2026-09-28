# Web Kiosk

Shows one web page full-screen on the display attached to the machine running
Home Assistant OS. It is a browser appliance: it does not know anything about
Home Assistant and works with any URL.

## Requirements

- Home Assistant OS on a Raspberry Pi 5 (`aarch64`).
- A DRM/KMS display. The primary target is the Raspberry Pi Touch Display 2 on
  the DSI connector; HDMI displays use the same code path.

Raspberry Pi 5 detects Touch Display 2 automatically with the Home Assistant OS
boot configuration. The panel is portrait (720x1280); set `rotation` to `90` or
`270` for landscape.

## Configuration

```yaml
url: "http://homeassistant.local:8123"
rotation: normal
chromium_flags: []
debug: false
```

### `url`

The page to show. Examples: `http://homeassistant.local:8123`,
`http://192.168.1.20:3000`, `http://dashboard.local:3000`.

The App container is not on the host network. Use a host name or IP address
that other devices on your LAN can reach; `localhost` refers to the App
container itself.

### `rotation`

`normal`, `90`, `180` or `270`. The compositor rotates the output
(Wayland output transform); touch input is rotated with it. If the picture is
upside down after choosing `90`, use `270`.

### `chromium_flags`

Extra Chromium flags, one flag per list entry, for example:

```yaml
chromium_flags:
  - "--lang=ko"
  - "--force-device-scale-factor=1.25"
  - "--disable-pinch"
```

Useful flags:

| Flag | Effect |
| ---- | ------ |
| `--lang=<code>` | Browser language (also the language Home Assistant picks by default). |
| `--force-device-scale-factor=<n>` | Zoom the whole page. |
| `--disable-pinch` | Disable pinch-to-zoom. |
| `--overscroll-history-navigation=0` | Disable swipe back/forward. |

### `debug`

Enables verbose logs from Cage/wlroots and Chromium. Leave it off in normal use.

## First run and signing in

The App opens the configured URL. If the site requires a login, sign in once
on the display. There is no on-screen keyboard yet, so connect a USB keyboard
for the first sign-in (see [Physical keyboards](#physical-keyboards)).

For Home Assistant, enable **Keep me logged in** on the login page.

## Credentials and persistent sessions

The App never asks for or stores credentials in its options. Chromium keeps its
profile in the App's private storage (`/data/chromium`): cookies,
`localStorage`, IndexedDB, site settings and permissions. A session created
once survives browser restarts, App restarts and reboots, like a normal
desktop browser.

- Chromium's password manager is disabled by policy, so it does not offer to
  save passwords.
- The profile is part of Home Assistant backups of this App (caches are
  excluded). Treat those backups as containing a signed-in browser session.
- To sign out completely, uninstall the App or remove `/data/chromium`.

## Crashes and restarts

The browser runs inside the Cage compositor, and Cage exits when the browser
exits. The App's service supervisor (s6) restarts both. If the page cannot be
loaded, for example while Home Assistant is still starting, Chromium retries
the error page automatically.

Stopping the App asks Chromium to shut down cleanly so the profile is flushed
to disk.

## Permissions

| Permission | Why |
| ---------- | --- |
| `devices: /dev/dri/card*` | Display mode setting (KMS). |
| `devices: /dev/dri/renderD*` | GPU rendering for the compositor and Chromium. |
| `devices: /dev/input/event*` | Touchscreen, keyboard and mouse. A range is listed because event numbers are not stable across boots. Paths that do not exist are ignored. |
| `udev: true` | Read-only host udev database. libinput ignores input devices that udev has not initialized. |

Not requested: host network, privileged capabilities (including
`SYS_ADMIN`), full hardware access, Home Assistant API, Supervisor API,
ingress or open ports. The App uses the Supervisor's default AppArmor
profile.

Known trade-offs:

- **Chromium runs with `--no-sandbox`.** Chromium's sandbox needs user
  namespaces, which Home Assistant App containers do not permit without
  `SYS_ADMIN`. The container is the isolation boundary. Only show sites you
  trust.
- **Compositor and browser run as root inside the container.** The
  compositor opens the display and input devices directly because there is no
  seat manager in the container.

### Physical keyboards

The App cannot take over the host's virtual terminal without extra
privileges. Keys typed on a physical keyboard are therefore expected to also
reach the Home Assistant OS console on that terminal. A keyboard attached to
the machine already gives access to that console. Do not leave an untrusted
keyboard attached.

## Troubleshooting

The App log (App page, **Log** tab) shows at startup the version, URL origin
(scheme, host and port), rotation, DRM devices and their
connectors, GPU render nodes, input devices, and the Cage and Chromium
versions. Cage then logs the DRM backend, the GL renderer and the selected
output.

Expected and harmless: Cage errors about the missing Xwayland binary (the App
has no X11 support), and Chromium errors about D-Bus (there is no D-Bus in the
container).

| Symptom | Check |
| ------- | ----- |
| App stops with "No accessible DRM/KMS display device found" | The log lists each `/dev/dri/card*`. `NOT accessible` means the node is not in the App's device list. No connectors means the display driver is not loaded (check the host `dmesg`). |
| Display stays dark, App running | The connector status in the log should be `connected`. Cage errors about DRM master mean another program owns the display. |
| No touch | The input device should be listed without `NOT accessible` or `not in udev database`, and marked `touchscreen`. |
| Touch offset after rotation | Report it with the log from a start with `debug: true`. |
| Slow rendering | The log should show `GPU render node ... accessible` and a hardware `GL renderer` from Cage (not `llvmpipe`). |
| Page shows but is logged out after restart | Sign in with **Keep me logged in**. Stopping or restarting the App keeps a new session; cutting power right after signing in can lose it. |

### Commands inside the App container

Open a shell in the container, for example from the host console
(`login`) or from an SSH App with protection mode disabled:

```sh
docker exec -it "$(docker ps -q -f name=web_kiosk)" bash
```

Then:

```sh
# DRM devices, connectors and their status
ls -l /dev/dri
for c in /sys/class/drm/card*-*; do echo "${c##*/}: $(cat "$c/status")"; done

# Outputs, modes and rotation as seen by the compositor
XDG_RUNTIME_DIR=/run/kiosk WAYLAND_DISPLAY=wayland-0 wlr-randr

# Input devices as libinput sees them
libinput list-devices

# Live touch events (Ctrl+C to stop); replace N with the touchscreen's number
libinput debug-events --device /dev/input/eventN

# Running processes (cage, chromium)
ps -o pid,etime,args | grep -E 'cage|chromium' | grep -v grep
```

To see Chromium's GPU status on the display, temporarily set `url` to
`chrome://gpu` and restart the App.

On the host (console `login`), kernel messages about the display and touch
controller:

```sh
dmesg | grep -i -E 'dsi|panel|touch|drm'
```
