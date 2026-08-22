#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# Persistent credentials for Mount It's private Samba service account
# ==============================================================================

MOUNTIT_DATA_DIR="${MOUNTIT_DATA_DIR:-/data}"
MOUNTIT_RUNTIME_DIR="${MOUNTIT_RUNTIME_DIR:-/tmp}"
MOUNTIT_PASSWORD_FILE="${MOUNTIT_PASSWORD_FILE:-${MOUNTIT_DATA_DIR}/mountit_password}"
MOUNTIT_RUNTIME_PASSWORD_FILE="${MOUNTIT_RUNTIME_PASSWORD_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit_password}"
MOUNTIT_SMB_AUTH_FILE="${MOUNTIT_SMB_AUTH_FILE:-${MOUNTIT_RUNTIME_DIR}/mountit_smbclient_auth}"

mountit::generate_password() {
    sed 's/[-]//g' /proc/sys/kernel/random/uuid | head -c 20
}

mountit::prepare_credentials() {
    local password="" password_tmp=""

    mkdir -p "$MOUNTIT_DATA_DIR" "$MOUNTIT_RUNTIME_DIR" || return 1

    if [[ -f "$MOUNTIT_PASSWORD_FILE" ]]; then
        IFS= read -r password < "$MOUNTIT_PASSWORD_FILE" || true
    fi

    # Mount It generates 20-character hexadecimal passwords. Regenerate an
    # empty, truncated, or otherwise invalid app-owned credential file.
    if [[ ! "$password" =~ ^[A-Fa-f0-9]{20}$ ]]; then
        password=$(mountit::generate_password)
        if [[ ! "$password" =~ ^[A-Fa-f0-9]{20}$ ]]; then
            return 1
        fi

        password_tmp=$(mktemp "${MOUNTIT_DATA_DIR}/.mountit_password.XXXXXX") || return 1
        if ! printf '%s\n' "$password" > "$password_tmp"; then
            rm -f "$password_tmp"
            return 1
        fi
        chmod 0600 "$password_tmp" || {
            rm -f "$password_tmp"
            return 1
        }
        mv -f "$password_tmp" "$MOUNTIT_PASSWORD_FILE" || {
            rm -f "$password_tmp"
            return 1
        }
    fi

    chmod 0600 "$MOUNTIT_PASSWORD_FILE" || return 1

    (umask 077; printf '%s\n' "$password" > "$MOUNTIT_RUNTIME_PASSWORD_FILE") || return 1
    (umask 077; {
        printf 'username = _mountit_\n'
        printf 'password = %s\n' "$password"
    } > "$MOUNTIT_SMB_AUTH_FILE") || return 1
    chmod 0600 "$MOUNTIT_RUNTIME_PASSWORD_FILE" "$MOUNTIT_SMB_AUTH_FILE" || return 1

    MOUNTIT_PASSWORD="$password"
}
