#!/bin/bash

set -Eeuo pipefail

readonly REPO_URL="${REPO_URL:-https://github.com/ljidi/proxmox-bootstrap.git}"
readonly REPO_BRANCH="${REPO_BRANCH:-main}"
readonly REPO_DIR="${REPO_DIR:-/root/proxmox-bootstrap}"
readonly ANSIBLE_DIR="$REPO_DIR/ansible"

log() {
    printf '[bootstrap] %s\n' "$*"
}

fail() {
    printf '[bootstrap] ERROR: %s\n' "$*" >&2
    exit 1
}

trap 'fail "An unexpected error occurred on line $LINENO."' ERR

if [[ $EUID -ne 0 ]]; then
    fail "Run this script as the root user."
fi

if [[ ! -r /etc/os-release ]]; then
    fail "Cannot detect the operating system."
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "debian" ]] && [[ "${ID_LIKE:-}" != *debian* ]]; then
    fail "This script is intended for Debian-based Proxmox VE hosts."
fi

configure_no_subscription_repositories() {
    local source_file

    log "Checking Proxmox repository configuration"
    for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$source_file" ]] || continue

        if grep -Eq '^[[:space:]]*(deb(-src)?[[:space:]].*|URIs:[[:space:]].*)https?://enterprise\.proxmox\.com/debian/' "$source_file"; then
            log "Switching enterprise repository to no-subscription in $source_file"
            sed -i -E \
                -e 's#https?://enterprise\.proxmox\.com/debian/#http://download.proxmox.com/debian/#g' \
                -e 's/(^|[[:space:]])pve-enterprise([[:space:]]|$)/\1pve-no-subscription\2/g' \
                -e 's/(^|[[:space:]])enterprise([[:space:]]|$)/\1no-subscription\2/g' \
                "$source_file"
        fi
    done
}

log "Updating package lists"
export DEBIAN_FRONTEND=noninteractive
readonly APT_UPDATE_LOG="$(mktemp)"
if apt-get update 2>&1 | tee "$APT_UPDATE_LOG"; then
    rm -f "$APT_UPDATE_LOG"
elif grep -Eq '401[[:space:]]+Unauthorized' "$APT_UPDATE_LOG" && grep -q "enterprise.proxmox.com/debian/" "$APT_UPDATE_LOG"; then
    rm -f "$APT_UPDATE_LOG"
    configure_no_subscription_repositories
    log "Retrying package list update with no-subscription repositories"
    apt-get update
else
    rm -f "$APT_UPDATE_LOG"
    fail "APT package-list update failed."
fi

log "Installing Git, certificates, sudo, Python, and SSH tools"
apt-get install -y --no-install-recommends ca-certificates git openssh-client python3 sudo

log "Installing Ansible"
if apt-cache show ansible >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends ansible
elif apt-cache show ansible-core >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends ansible-core
else
    fail "No Ansible package was found in the configured apt repositories."
fi

log "Preparing repository at $REPO_DIR"

if [[ -e "$REPO_DIR" && ! -d "$REPO_DIR" ]]; then
    fail "$REPO_DIR exists and is not a directory."
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
    git -C "$REPO_DIR" fetch --prune origin
    git -C "$REPO_DIR" checkout --quiet "$REPO_BRANCH"
    git -C "$REPO_DIR" pull --ff-only origin "$REPO_BRANCH"
else
    [[ -e "$REPO_DIR" ]] && fail "$REPO_DIR exists but is not a Git repository."

    PARENT_DIR="$(dirname "$REPO_DIR")"
    readonly PARENT_DIR
    TEMP_DIR="$(mktemp -d "$PARENT_DIR/.proxmox-bootstrap.XXXXXX")"
    readonly TEMP_DIR
    trap 'rm -rf "${TEMP_DIR:-}"' EXIT

    git clone --branch "$REPO_BRANCH" --single-branch "$REPO_URL" "$TEMP_DIR/repository"
    mv "$TEMP_DIR/repository" "$REPO_DIR"
    rm -rf "$TEMP_DIR"
    trap - EXIT
fi

log "Verifying Git and Ansible"
git --version
ansible --version | head -n 1

log "Testing the repository Ansible setup"
cd "$ANSIBLE_DIR"
ansible local -m ping

log "Running the complete Proxmox and VM setup"
ansible-playbook playbooks/setup-all.yml

log "Bootstrap complete"
printf '\nRepository: %s\n' "$REPO_DIR"
printf 'Ansible directory: %s\n' "$ANSIBLE_DIR"
printf 'Provisioning playbook: %s\n' "$ANSIBLE_DIR/playbooks/setup-all.yml"