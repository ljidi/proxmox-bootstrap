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
- Falls back to Proxmox no-subscription feeds if an enterprise repository returns an HTTP 401 during the APT update.
- Clones the repository to `/root/proxmox-bootstrap` when it is absent.
- Fetches and fast-forwards `/root/proxmox-bootstrap` when it already exists.
- Uses the repository-managed `ansible/inventory.ini` and `ansible/ansible.cfg` files.
- Tests the local Ansible connection.

## Run further setup

```sh
cd /root/proxmox-bootstrap/ansible
ansible-playbook playbooks/setup-all.yml
```

The master playbook runs the four stages in order. It requires a working Proxmox VE host, `local-lvm` storage, the `vmbr0` bridge, DHCP on the guest network, and network access from the guests to Debian package repositories and container registries. The first stage enables snippets on the `local` directory storage and configures cloud-init to install the QEMU guest agent on new VMs. All four stages run without prompts. Existing VM IDs `100` or `101` are not overwritten; choose different IDs in the playbook variables or remove the existing VMs before the first full run.

The ordered playbooks are:

- `01-site.yml` creates the Debian 13 cloud-init template, prepares local cloud-init vendor data to install the QEMU guest agent, and creates the root-only Proxmox-to-VM Ed25519 keypair.
- `02-devops-vm.yml` creates the Debian VM and starts Forgejo 17 with PostgreSQL in a Podman pod.
- `03-automation-vm.yml` creates the automation VM, installs Ansible and rootless Podman, and prepares Forgejo Runner.
- `04-forgejo-runner-config.yml` creates the Forgejo administrator, organization and repository, then registers and starts the runner.

To stop and permanently remove VMs `100` and `101` and their disks, run the separate, destructive revert playbook:

```sh
cd /root/proxmox-bootstrap/ansible
ansible-playbook playbooks/revert-vms.yml
```

It skips VM IDs that do not exist and does not remove the Debian template.

```sh
cd /root/proxmox-bootstrap/ansible
ansible-playbook playbooks/01-site.yml
ansible-playbook playbooks/02-devops-vm.yml
ansible-playbook playbooks/03-automation-vm.yml
ansible-playbook playbooks/04-forgejo-runner-config.yml
```

The final stage prints the Forgejo URL and generated administrator credentials. The password is a randomized 256-bit value stored in `/etc/forgejo/admin-credentials.json` on the Forgejo VM with root-only permissions; it reuses saved credentials on reruns rather than resetting the password. Forgejo's install lock is enabled automatically, so the web UI is ready at `http://<forgejo-vm-ip>:3000/` without completing the setup wizard. The stage also creates the `environment` organization and its private `infrastructure` repository and registers the runner at organization scope.

The VM defaults are Forgejo ID `100` and automation ID `101`, on `local-lvm`. Both use DHCP and QEMU guest-agent IP discovery. The automation VM prepares a Forgejo Runner in a rootless Podman pod, with an `ansible` label backed by a Debian job image. It displays the generated Ed25519 deployment public key; add that key to `authorized_keys` on hosts that workflows should manage. Workflows can use the private key at `/run/secrets/ansible_ed25519`.

The included `.forgejo/workflows/ansible-syntax.yml` runs Ansible syntax checks on pushes and manual dispatch. For deployment workflows, use `runs-on: ansible` and your repository's inventory, for example `ansible-playbook -i inventory/production.yml playbooks/deploy.yml --private-key /run/secrets/ansible_ed25519`. Override `forgejo_server_url` when running `forgejo-runner-config.yml` if Forgejo is reached through a stable DNS name or HTTPS endpoint; otherwise the playbook uses the DHCP address reported by the Forgejo VM's guest agent. A DHCP reservation is recommended if using the default URL.

Forgejo runners execute workflow code. The runner is registered to the `environment` organization, so it can run workflows from repositories in that organization; workflow jobs can access the deployment key and rootless Podman service on the dedicated automation VM. Allow only trusted contributors to change workflows in that organization and do not use it for untrusted pull requests. The default Forgejo URL uses HTTP, so use a trusted network or configure Forgejo behind HTTPS.

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
