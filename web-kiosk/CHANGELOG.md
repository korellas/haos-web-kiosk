# Changelog

## 0.1.1

- Hide Cage's cursor when a touchscreen is connected, including before the
  browser receives pointer focus. Keep the cursor on pointer-only displays.

## 0.1.0

- Initial release: Cage (Wayland, DRM/KMS) with Chromium showing one configured
  URL on the local display.
- Persistent Chromium profile in the App's `/data`.
- Output rotation (`normal`, `90`, `180`, `270`) with touch input following
  the rotation.
- Automatic restart of compositor and browser by s6.
