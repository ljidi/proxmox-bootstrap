# Copilot Instructions

## Scope

This repository bootstraps a freshly installed Proxmox VE host and creates Debian guests. Its entry points are:

- `scripts/bootstrap.sh` prepares a Debian/Proxmox host, clones or updates this repository under `/root/proxmox-bootstrap`, installs Ansible, and verifies the local inventory.
- `ansible/playbooks/01-site.yml` applies host configuration: base packages, `qemu-server`, a Debian 13 cloud-init VM template, and the VM SSH keypair.
- `ansible/playbooks/02-devops-vm.yml` clones that template, configures DHCP and SSH, discovers the guest IP through QEMU guest agent, then deploys Forgejo and PostgreSQL in a Podman pod.
- `ansible/playbooks/03-automation-vm.yml` creates a DHCP automation VM, installs Ansible and rootless Podman, prepares Forgejo Runner, and creates a deployment SSH keypair.
- `ansible/playbooks/04-forgejo-runner-config.yml` generates a Forgejo administrator, creates the `environment` organization and private `infrastructure` repository, registers the runner at organization scope, and configures the runner connection.
- `ansible/playbooks/setup-all.yml` statically imports the four numbered playbooks in sequence for unattended setup.
- `.forgejo/workflows/ansible-syntax.yml` demonstrates running Ansible checks on the runner's `ansible` label.

Most changes should keep the bootstrap and Ansible layers compatible: the bootstrap script defines where the repository and Ansible workspace live, while the playbooks configure the Proxmox host and its guests.

## Working directory and execution

Run repository-managed Ansible commands from `ansible/` so `ansible.cfg` and `inventory.ini` are discovered:

```sh
cd /root/proxmox-bootstrap/ansible
ansible local -m ping
ansible-playbook playbooks/setup-all.yml
```

The inventory contains only the `local` host, using localhost and `/usr/bin/python3`. The playbook is deliberately local-host configuration and runs with privilege escalation; do not replace `localhost` with remote SSH hosts without also updating both the inventory and playbook execution model.

The bootstrap script is root-only and Debian-family-only. It performs APT updates and package installation, so validate it on a disposable Proxmox host or container rather than running it in-place on a developer workstation.

## Build, validation, and lint commands

There is no Makefile, package manifest, test suite, or configured `ansible-lint`/ShellCheck setup.

Syntax and connectivity checks:

```sh
cd /root/proxmox-bootstrap/ansible
ansible local -m ping
ansible-playbook --syntax-check playbooks/01-site.yml
ansible-playbook --syntax-check playbooks/02-devops-vm.yml
ansible-playbook --syntax-check playbooks/03-automation-vm.yml
ansible-playbook --syntax-check playbooks/04-forgejo-runner-config.yml
ansible-playbook --syntax-check playbooks/setup-all.yml
```

Run a specific playbook by its path (the DevOps VM playbook needs a created template, an unused VM ID, DHCP on the guest network, and a working QEMU guest agent; `site.yml` creates the SSH keys):

```sh
cd /root/proxmox-bootstrap/ansible
ansible-playbook playbooks/01-site.yml
ansible-playbook playbooks/02-devops-vm.yml
ansible-playbook playbooks/03-automation-vm.yml
ansible-playbook playbooks/04-forgejo-runner-config.yml
```

For a local source-tree syntax-only check without installing or applying anything:

```sh
bash -n scripts/bootstrap.sh
cd ansible
ansible-playbook --syntax-check playbooks/01-site.yml
```

ShellCheck is not configured or guaranteed to be installed. If it is available, additionally run:

```sh
shellcheck scripts/bootstrap.sh
```

An Ansible dry run is not a reliable substitute for a Proxmox host test for this playbook: its VM operations use `qm` commands and command-module registration, and VM creation side effects require the real PVE environment.

## Architecture and state model

`ansible/ansible.cfg` uses `inventory.ini`, disables host-key checking and retry files, selects `/usr/bin/python3`, enables become with sudo, and expects roles under `ansible/roles/`.

`ansible/inventory.ini` maps the `local` host to the local connection plugin. `ansible/playbooks/01-site.yml` gathers facts and applies configuration directly on the host.

The host-setup playbook uses a VM-ID existence check as the template creation guard:

- `qm status 9000` determines whether template setup is needed.
- A nonzero status controls directory creation, image download, VM creation/import/configuration, and conversion to a template.
- VM and storage names are centralized in play vars: `debian_template_vmid`, `debian_template_name`, `debian_template_storage`, `debian_cloud_image_url`, and `debian_cloud_image_path`.
- `01-site.yml` creates an Ed25519 VM-access keypair at `/root/.ssh/proxmox-vm` and `/root/.ssh/proxmox-vm.pub`; the guest playbooks use that keypair by default.

The bootstrap script preserves an idempotent repository setup:

- Existing repositories are reset to the configured origin, fetched, checked out to `REPO_BRANCH`, and fast-forwarded.
- Missing repositories are cloned into a temporary sibling directory and moved into place.
- Unexpected existing paths and non-Git directories fail explicitly.
- `REPO_URL`, `REPO_BRANCH`, and `REPO_DIR` override the defaults.

The DevOps guest playbook expects the Debian template created by `01-site.yml`. It refuses to overwrite a VM ID already in use, clones the template to `local-lvm`, configures DHCP via cloud-init, and injects a public SSH key. It uses QEMU guest agent to discover the assigned IPv4 address, then adds the VM to an in-memory inventory so Ansible can configure a root-managed Podman Quadlet pod. Forgejo and PostgreSQL persist data in named volumes; the generated database credentials are stored in a root-only environment file on the guest. The Forgejo install lock is enabled so the web interface is ready without an interactive setup wizard.

The automation VM playbook creates VM `101` by default, installs Ansible, and prepares Forgejo Runner with rootless Podman without registering it. The separate runner configuration playbook expects Forgejo VM `100` and automation VM `101` to be running. It creates the `proxmox-admin` Forgejo administrator with a random password, stores the credentials in `/etc/forgejo/admin-credentials.json` on the Forgejo VM with root-only permissions, and reports them in the final task; it reuses those credentials on reruns. It then idempotently creates the `environment` organization and its private `infrastructure` repository through the Forgejo API, generates and persists a Forgejo CLI runner secret on the Forgejo VM, registers the runner at the organization scope, and writes the returned UUID and secret into the automation VM's runner configuration. The runner's `ansible` label uses a Debian container image with Ansible installed; the automation VM's deployment key is mounted read-only into workflow containers at `/run/secrets/ansible_ed25519`. Organization-scoped runner workflows are remote code execution and can access this key and the automation user's Podman service, so ensure every repository and workflow in the organization is trusted. The `setup-all.yml` playbook imports all four numbered stages in order; none require interactive input.

## Repository conventions

- Use fully qualified Ansible module names, matching the existing `ansible.builtin.*` modules.
- Keep play vars as variables rather than duplicating VM ID, name, storage, URL, or image path literals in tasks.
- Preserve the `qm status` guard for template creation. Use `failed_when: false` and explicit `changed_when` semantics where commands are probes or may legitimately leave state unchanged.
- Keep the guest-creation playbook's collision check: it must fail rather than repurpose an existing VM ID.
- Keep Forgejo Runner registration scoped to the `environment` organization and protect every workflow that can access the mounted Ansible deployment key.
- Prefer `argv` lists for `qm`, `apt`, `git`, and other command invocations so arguments are not reparsed by a shell.
- Keep package installation with APT and keep Proxmox-specific commands in the playbook rather than moving them into the bootstrap script.
- Maintain Bash strict mode (`set -Eeuo pipefail`) and explicit root, Debian, path, and repository checks in `scripts/bootstrap.sh`.
- The bootstrap and playbook both use `main`/`/root/proxmox-bootstrap` assumptions in their defaults; an override must remain consistent for `REPO_DIR` and the derived `ANSIBLE_DIR`.
- Preserve existing root-home paths and PVE storage conventions unless the user explicitly requests a generalization.
