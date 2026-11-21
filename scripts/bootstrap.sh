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

log "Updating package lists"
export DEBIAN_FRONTEND=noninteractive
apt-get update

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

    readonly PARENT_DIR
    PARENT_DIR="$(dirname "$REPO_DIR")"
    readonly TEMP_DIR
    TEMP_DIR="$(mktemp -d "$PARENT_DIR/.proxmox-bootstrap.XXXXXX")"
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

log "Bootstrap complete"
printf '\nRepository: %s\n' "$REPO_DIR"
printf 'Ansible directory: %s\n' "$ANSIBLE_DIR"
printf 'Run the local playbook with:\n  cd %q\n  ansible-playbook playbooks/site.yml\n' "$ANSIBLE_DIR"