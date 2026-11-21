# proxmox-bootstrap

Bootstrap a freshly installed Proxmox VE host with Git and Ansible, clone this repository under `/root`, and create the local Ansible workspace.

## One-command installation

Log in as `root` and run:

```sh
curl -fsSL https://raw.githubusercontent.com/ljidi/proxmox-bootstrap/main/scripts/bootstrap.sh | bash
```

If `curl` is unavailable, use:

```sh
wget -qO- https://raw.githubusercontent.com/ljidi/proxmox-bootstrap/main/scripts/bootstrap.sh | bash
```

The script is idempotent:

- Installs Git and base tools, then installs Ansible after updating APT.
- Clones the repository to `/root/proxmox-bootstrap` when it is absent.
- Fetches and fast-forwards `/root/proxmox-bootstrap` when it already exists.
- Uses the repository-managed `ansible/inventory.ini` and `ansible/ansible.cfg` files.
- Tests the local Ansible connection.

## Run further setup

```sh
cd /root/proxmox-bootstrap/ansible
ansible-playbook playbooks/site.yml
```

The `site.yml` playbook installs base packages and `qemu-server`, downloads a Debian 13 generic cloud image, and creates VM template `debian-13-template` with VM ID `9000` on `local-lvm`. It enables DHCP cloud-init networking and skips creation when VM ID `9000` already exists.

Place additional playbooks in `/root/proxmox-bootstrap/ansible/playbooks` and additional roles in `/root/proxmox-bootstrap/ansible/roles`.

## Repository options

Environment variables can override the defaults:

```sh
REPO_URL=https://example.invalid/organization/proxmox-bootstrap.git \
REPO_BRANCH=main \
REPO_DIR=/root/proxmox-bootstrap \
curl -fsSL https://raw.githubusercontent.com/ljidi/proxmox-bootstrap/main/scripts/bootstrap.sh | bash
```

Run a local copy instead of piping it directly:

```sh
bash /root/proxmox-bootstrap/scripts/bootstrap.sh
```
