#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Log the hardware the kiosk will use and stop early if there is no display.
# ==============================================================================

# Log only the origin; URL paths can also contain session tokens.
redact_url() {
    if [[ "${1}" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)([^/?#]+) ]]; then
        local authority=${BASH_REMATCH[2]##*@}
        printf '%s%s' "${BASH_REMATCH[1]}" "${authority}"
    else
        printf '<redacted>'
    fi
}

# Succeeds when the device cgroup allows opening the node.
can_open() {
    { : <> "${1}"; } 2> /dev/null
}

driver_of() {
    basename "$(readlink -f "/sys/class/drm/${1}/device/driver")"
}

bashio::log.info "Web Kiosk ${KIOSK_VERSION:-unknown} on $(uname -m)"
bashio::log.info "URL: $(redact_url "$(bashio::config 'url')")"
bashio::log.info "Rotation: $(bashio::config 'rotation')"
while read -r flag; do
    [[ -n "${flag}" ]] && bashio::log.info "Extra Chromium flag: ${flag%%=*}"
done <<< "$(bashio::config 'chromium_flags')"
bashio::log.info "Compositor: Cage $(cage -v 2>&1 | awk '{print $NF}') (wlroots DRM/KMS backend)"
bashio::log.info "Browser: $(/usr/lib/chromium/chromium --version 2>/dev/null)"

# Display controllers: DRM card nodes that have connectors.
kms_usable=false
for card_path in /sys/class/drm/card[0-9]; do
    [[ -e "${card_path}" ]] || continue
    card=$(basename "${card_path}")
    connectors=()
    for connector_path in "${card_path}/${card}"-*; do
        [[ -e "${connector_path}/status" ]] || continue
        connectors+=("${connector_path##*/"${card}"-}=$(< "${connector_path}/status")")
    done

    if ! can_open "/dev/dri/${card}"; then
        access="NOT accessible"
    elif (( ${#connectors[@]} > 0 )); then
        access="accessible"
        kms_usable=true
    else
        access="accessible, no connectors (render only)"
    fi
    bashio::log.info "DRM /dev/dri/${card} [$(driver_of "${card}")] ${access} ${connectors[*]}"
done

gpu_render=false
for render_path in /sys/class/drm/renderD*; do
    [[ -e "${render_path}" ]] || continue
    node=$(basename "${render_path}")
    if can_open "/dev/dri/${node}"; then
        gpu_render=true
        bashio::log.info "GPU render node /dev/dri/${node} [$(driver_of "${node}")] accessible"
    else
        bashio::log.warning "GPU render node /dev/dri/${node} [$(driver_of "${node}")] NOT accessible"
    fi
done
if bashio::var.true "${gpu_render}"; then
    bashio::log.info "Hardware acceleration: GPU render node available"
else
    bashio::log.warning "Hardware acceleration: no usable GPU render node; rendering may fall back to software"
fi

# Input devices. libinput ignores devices without an entry in the udev database.
input_found=false
for event_path in /sys/class/input/event[0-9]*; do
    [[ -e "${event_path}" ]] || continue
    event=$(basename "${event_path}")
    name=$(< "${event_path}/device/name")
    udev_data="/run/udev/data/c$(< "${event_path}/dev")"
    notes=()
    if ! can_open "/dev/input/${event}"; then
        notes+=("NOT accessible")
    elif [[ ! -e "${udev_data}" ]]; then
        notes+=("not in udev database, ignored by libinput")
    else
        input_found=true
    fi
    if [[ -e "${udev_data}" ]] && grep -q '^E:ID_INPUT_TOUCHSCREEN=1$' "${udev_data}"; then
        notes+=("touchscreen")
    fi
    bashio::log.info "Input /dev/input/${event} \"${name}\" ${notes[*]}"
done
if ! bashio::var.true "${input_found}"; then
    bashio::log.warning "No usable input devices; the display will work without touch"
fi

if ! bashio::var.true "${kms_usable}"; then
    bashio::exit.nok "No accessible DRM/KMS display device found. Is a display connected and enabled?"
fi
