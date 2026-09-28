# HAOS Web Kiosk

A Home Assistant OS App (formerly "add-on") that shows one configured URL
full-screen on the display physically attached to the Home Assistant machine.

It is a generic browser appliance, not a dashboard. It has no Home Assistant
integration, has no username or password options and does not log in for you.
Home Assistant is just one URL you can point it at; a dashboard served from
another project works the same way.

```text
Cage + Chromium + persistent profile + URL
```

## Supported hardware

| | |
| - | - |
| Board | Raspberry Pi 5 (`aarch64`) running Home Assistant OS |
| Display | Raspberry Pi Touch Display 2 (DSI) — primary target. Other DRM/KMS displays (HDMI) use the same code path but are less tested. |
| Input | Touchscreens, keyboards and mice exposed through Linux evdev/libinput |

One display at a time. Other architectures will be added once the Raspberry Pi
5 path is proven.

## Installation

1. In Home Assistant, open **Settings → Apps → App store**, open the menu
   (⋮) → **Repositories**, and add
   `https://github.com/korellas/haos-web-kiosk`.

   [![Add repository](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fkorellas%2Fhaos-web-kiosk)

2. Install **Web Kiosk**, set `url` on the **Configuration** tab, and start it.
   The App starts automatically at boot.

## Configuration

| Option | Description |
| ------ | ----------- |
| `url` | Page to show. The App is not on the host network, so use an address reachable from your LAN (not `localhost`). |
| `rotation` | `normal`, `90`, `180`, `270`. Applied by the compositor; touch follows it. Touch Display 2 is portrait, so use `90` or `270` for landscape. |
| `chromium_flags` | Extra Chromium flags, one per entry, e.g. `--lang=ko`. |
| `debug` | Verbose compositor and browser logs. |

Details: [web-kiosk/DOCS.md](web-kiosk/DOCS.md).

## First run, credentials and sessions

On first start the display shows the configured page. If the page requires a
login, sign in once on the display. There is no on-screen keyboard in this
version; attach a USB keyboard for the first sign-in (see the keyboard note
under [Security](#permissions-and-security)).

The App does not store a username or password in its options. Chromium uses a
persistent profile in the App's private storage (`/data/chromium`), so cookies,
`localStorage`, IndexedDB and site permissions survive browser restarts, App restarts and
reboots, just like a desktop browser. For Home Assistant, choose **Keep me
logged in**. Chromium's password manager is disabled by policy.

The profile is included in Home Assistant backups of the App (caches
excluded), so a backup contains a signed-in browser session.

## Architecture

```text
┌──────────────────────── Home Assistant OS host ─────────────────────────┐
│  kernel: DRM/KMS (vc4 display, v3d GPU)   evdev (/dev/input/event*)     │
│  host udev database (/run/udev, mounted read-only into the App)         │
│                                                                         │
│  ┌──────────────────── Web Kiosk App container ──────────────────────┐  │
│  │ s6-overlay                                                        │  │
│  │  ├─ cont-init: kiosk-preflight  (log hardware, fail if no KMS)    │  │
│  │  └─ service: kiosk  (restarted by s6 when it exits)               │  │
│  │       └─ cage  (Wayland compositor; DRM backend, libinput,        │  │
│  │           │     libseat "noop": opens devices directly)           │  │
│  │           └─ kiosk-session  (wlr-randr: rotate output)            │  │
│  │                └─ exec chromium --ozone-platform=wayland --kiosk  │  │
│  │                      --user-data-dir=/data/chromium  <url>        │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Cage** is a single-application Wayland kiosk compositor. It exits when its
  client exits, so a browser crash restarts compositor and browser together
  through s6. On stop, the service sends `SIGTERM` to Chromium first so the
  profile is flushed, then Cage exits.
- **Rotation** is a Wayland output transform set with `wlr-randr` (Cage
  implements wlr-output-management) before Chromium starts.
- **Touch alignment with rotation.** wlroots rotates absolute touch
  coordinates only when the touch device is mapped to an output. Stock Cage
  maps a device only if udev gives it a `WL_OUTPUT` property, which the Home
  Assistant OS udev database does not. The image therefore builds Cage from
  the release tarball with a small patch
  ([`web-kiosk/patches`](web-kiosk/patches)) that maps the cursor to the
  output when exactly one output exists. This follows the approach of the
  open upstream proposal
  [cage-kiosk/cage#388](https://github.com/cage-kiosk/cage/pull/388).
- **No Xorg, no window manager, no desktop.** Nothing in this design needs
  them. The Xorg-based HAOS kiosks studied for this project request
  `SYS_ADMIN`, used to remount `/dev` around Xorg's `/dev/tty0` handling.
- **Base image:** pinned `ghcr.io/home-assistant/base` (Alpine) in the
  Dockerfile; no `build.yaml`.

### Extension points (not implemented)

Display on/off, brightness, reload and navigation are planned as later,
separate features. The runtime directory `/run/kiosk` holds the compositor's
Wayland socket (usable with `wlr-randr --on/--off`) and the browser PID. A
future control service must listen only inside the container or behind
Home Assistant ingress; an unauthenticated LAN interface is out of scope.

## Permissions and security

| Requested | Reason |
| --------- | ------ |
| `devices: /dev/dri/card*` | KMS mode setting on the display controller. |
| `devices: /dev/dri/renderD*` | GPU rendering. |
| `devices: /dev/input/event*` | Touch, keyboard, mouse. Event numbers change between boots, so a range of nodes is listed in `config.yaml`; missing paths are ignored. |
| `udev: true` | Read-only host udev database; libinput requires it. |

Not requested: `host_network`, `privileged` capabilities, `full_access`,
`homeassistant_api`, `hassio_api`, `auth_api`, ingress, ports. The
Supervisor's default AppArmor profile applies; a custom profile will be added
after tracing the App on hardware.

Trade-offs:

- Chromium runs with `--no-sandbox`, because its sandbox needs user namespaces
  that App containers do not allow without `SYS_ADMIN`. Only display sites you
  trust.
- Cage and Chromium run as root inside the container.
- The App cannot take over the host's virtual terminal, so keys typed on a
  physical keyboard are expected to also reach the Home Assistant OS console.
  A keyboard attached to the host already grants console access.

## Troubleshooting

The App log shows at startup: version, URL origin (scheme, host and port),
rotation, DRM cards and connector status, GPU render nodes, input
devices and whether libinput can use them, and the Cage and Chromium versions.
Cage then logs the DRM backend, GL renderer and chosen output.

Diagnostic commands for DRM outputs, the renderer, libinput devices, touch
events, Chromium GPU state and crashes are in
[web-kiosk/DOCS.md](web-kiosk/DOCS.md#troubleshooting).

## Development

Repository layout:

```text
repository.yaml            App repository definition
web-kiosk/
  config.yaml              App manifest (options, devices)
  Dockerfile               Cage build stage + runtime image
  patches/                 Patch applied to Cage
  rootfs/                  s6 scripts, kiosk-session, Chromium policy
  DOCS.md, README.md, CHANGELOG.md, translations/
.github/workflows/         Lint, build and publish
```

Build locally (on an arm64 machine, or with QEMU elsewhere):

```sh
docker buildx build --platform linux/arm64 -t local/web-kiosk web-kiosk
```

Test on the real device: copy `web-kiosk/` to `/addons/web-kiosk` on the Home
Assistant host (Samba or SSH App), comment out `image:` in its `config.yaml`,
then install it from **Local apps**. The Supervisor builds the image on the
device.

### Releases

`version` in `web-kiosk/config.yaml` is the release version.

1. Update `version` and `web-kiosk/CHANGELOG.md` in a pull request. CI lints
   and builds the image without publishing.
2. Merge to `main`. CI publishes `ghcr.io/korellas/aarch64-haos-web-kiosk`
   and the multi-arch manifest `ghcr.io/korellas/haos-web-kiosk` with tags
   `<version>` and `latest`, signed with Cosign. A version that already exists
   is not overwritten.
3. Once, after the first publish: make the GHCR package public, otherwise Home
   Assistant cannot pull it.

## License

MIT. Cage is MIT-licensed; the patch in `web-kiosk/patches` is under Cage's
license.
