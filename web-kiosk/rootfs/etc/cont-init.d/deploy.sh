#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

readonly deploy_dir=/data/deploy
readonly service_down=/etc/services.d/deploy-sftp/down

install -d -o root -g root -m 0755 "${deploy_dir}"
install -d -o kiosk-deploy -g kiosk-deploy -m 0755 "${deploy_dir}/site"
install -d -m 0755 /run/sshd
touch "${service_down}"
rm -f "${deploy_dir}/authorized_keys"

keys_file=$(mktemp)
trap 'rm -f "${keys_file}"' EXIT
if ! kiosk-authorized-keys /data/options.json > "${keys_file}"; then
    bashio::log.error "Invalid deployment public key; SFTP is disabled"
    exit 0
fi
if [[ ! -s "${keys_file}" ]]; then
    bashio::log.info "SFTP deployment is disabled (no public keys)"
    exit 0
fi

install -o root -g root -m 0644 "${keys_file}" "${deploy_dir}/authorized_keys"
if [[ ! -e "${deploy_dir}/ssh_host_ed25519_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "${deploy_dir}/ssh_host_ed25519_key"
fi
chmod 0600 "${deploy_dir}/ssh_host_ed25519_key"
ssh-keygen -lf "${deploy_dir}/ssh_host_ed25519_key.pub" \
    | while read -r fingerprint; do
        bashio::log.info "SFTP host key: ${fingerprint}"
    done

if ! sshd -t -f /etc/ssh/sshd_config_kiosk; then
    bashio::log.error "Invalid SFTP server configuration; SFTP is disabled"
    exit 0
fi
rm -f "${service_down}"
bashio::log.info "SFTP deployment ready on container port 2222"
