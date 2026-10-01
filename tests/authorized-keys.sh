#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ssh-keygen -q -t ed25519 -N '' -f "$tmp/client"
key=$(< "$tmp/client.pub")
jq -n --arg key "$key" '{deploy_authorized_keys: [$key]}' > "$tmp/options.json"

expected=${key% *}
actual=$("$root/web-kiosk/rootfs/usr/bin/kiosk-authorized-keys" "$tmp/options.json")
[[ "$actual" == "$expected" ]]

jq -n --arg key "command=sh $key" '{deploy_authorized_keys: [$key]}' > "$tmp/options.json"
if "$root/web-kiosk/rootfs/usr/bin/kiosk-authorized-keys" "$tmp/options.json" > /dev/null 2>&1; then
    echo "SSH key options must be rejected" >&2
    exit 1
fi

jq -n '{deploy_authorized_keys: []}' > "$tmp/options.json"
[[ -z "$("$root/web-kiosk/rootfs/usr/bin/kiosk-authorized-keys" "$tmp/options.json")" ]]
