# Infrastructure as Code (Ansible + KVM / Libvirt)

This folder contains a production-ready Ansible automation suite to provision, configure, and manage the Forgejo Git Server and CI/CD runners across any target environment:
- **Local or Remote KVM / Libvirt VMs** (using [`micrometre/ansible-kvm`](https://github.com/micrometre/ansible-kvm) `virtualization` and `vm-manager` roles with cloud-init, static IPs, qcow2 snapshots, and remote access via `virt-manager`, `virsh`, and Cockpit Web UI)
- **Bare-metal servers**
- **Cloud instances** (Hetzner, AWS, DigitalOcean, Linode, etc.)

---

## Directory Structure

```text
ansible/
├── ansible.cfg                        # Preconfigured SSH, pipelining, and inventory settings
├── inventory/
│   ├── hosts.ini                      # Target server & runner definitions ([git_servers], [git_runners])
│   └── group_vars/
│       └── all.yml                    # Configurable ports, versions, paths, credentials, runner labels
├── playbooks/
│   ├── site.yml                       # Master playbook: provisions git_servers and git_runners
│   ├── configure-kvm.yml              # Host KVM/libvirt setup, VM creation, status, overview, and snapshots
│   ├── deploy-git-server.yml          # Fast app deployment (skips OS packages)
│   ├── deploy-runner.yml              # Provisions and registers Forgejo Actions runners
│   ├── provision-kvm.yml              # Turnkey: launches KVM Git Server VM ('git-server') and provisions it
│   ├── provision-runner-kvm.yml       # Turnkey: launches KVM Runner VM ('git-runner') and registers with Forgejo
│   └── restore.yml                    # Restores host backup archive onto target server(s)
└── roles/
    ├── virtualization/                # Installs QEMU/KVM, libvirt, Cockpit Web UI (:9090), and remote qemu+ssh access
    ├── vm-manager/                    # Manages KVM cloud-image VMs, cloud-init, static IPs, and qcow2 snapshots
    ├── common/                        # OS baseline: apt cache, essential tools, SSH keys
    ├── docker/                        # Installs Docker CE, Compose v2, and Buildx
    ├── git_server/                    # Templates .env & compose, enables Actions, starts containers
    ├── forgejo_runner/                # Installs Forgejo Runner, auto-fetches token, registers & runs daemon
    └── restore_backup/                # Auto-locates, transfers, and restores host backup archive
```

---

## Roles Overview

### 1. `virtualization`
* Verifies CPU hardware virtualization (`vmx` / `svm`) support.
* Installs QEMU/KVM, `libvirt-daemon-system`, `libvirt-clients`, `virt-manager`, `virtinst`, `genisoimage`, `netcat-openbsd`, `ovmf`, and `swtpm`.
* Installs and enables **Cockpit + Cockpit Machines** (`cockpit.socket` on port `9090`) for browser-based remote VM management.
* Adds the deploy user (`ubuntu`) to the `libvirt` and `kvm` groups and configures `/etc/libvirt/libvirtd.conf` (`unix_sock_group = "libvirt"`, `unix_sock_rw_perms = "0770"`) so remote workstations can manage VMs passwordlessly over `qemu+ssh://ubuntu@<HOST_IP>/system`.
* Defines, starts, and autostarts the `default` (`virbr0`, `192.168.122.0/24`) NAT network and enables IPv4 forwarding.

### 2. `vm-manager`
* **Cloud Image Caching**: Downloads Ubuntu (`noble` 24.04, `jammy` 22.04, `focal` 20.04) or Debian (`debian12`, `debian11`) cloud images once to `/home/ubuntu/vm-images/` and `/var/lib/libvirt/images/`.
* **Fast Overlay Provisioning**: Creates thin-provisioned qcow2 overlay disks (`/usr/bin/qemu-img create -b ...`) and automatically expands the root filesystem inside the guest via cloud-init `growpart`.
* **Cloud-Init & Static Networking**: Generates `user-data`, `meta-data`, and `network-config` (Netplan v2 matching `en*` VirtIO NICs), injects all host `~/.ssh/*.pub` keys, and boots the VM via `virt-install --connect qemu:///system`.
* **Inventory & SSH Config Sync**: Automatically updates `ansible/inventory/hosts.ini`, `ansible/inventory/vm-<name>.yml`, and `~/.ssh/config`.
* **Snapshots & Lifecycle**: Supports `vm_action` values `create`, `status`, `overview`, `snapshot_create`, `snapshot_list`, `snapshot_revert`, `snapshot_delete`, and `snapshot_clone`, plus `vm_cleanup=true`.

### 3. `common`
* Updates apt package cache.
* Installs baseline utilities (`curl`, `wget`, `git`, `make`, `jq`, `unzip`, `ca-certificates`, `gnupg`, `htop`, `net-tools`).
* Ensures the deployment user exists with passwordless sudo access.

### 4. `docker`
* Installs Docker CE Engine (`docker.io`), Docker Compose v2 CLI plugin (`docker-compose-v2`), and Docker Buildx (`docker-buildx`).
* Adds the deploy user to the `docker` group and resets the SSH connection so group membership takes effect immediately.

### 5. `git_server`
* Creates application directory structure (`data/forgejo`, `data/postgres`, `make/`, `scripts/`).
* Templates `docker-compose.yml` and `.env` from Jinja2 templates using inventory variables (including `FORGEJO__actions__ENABLED=true`, `FORGEJO__actions__DEFAULT_ACTIONS_URL=https://github.com`, and release attachment limits up to 1024 MB).
* Starts containers (`docker compose up -d`), waits for HTTP readiness on port `3000`, and creates the default admin user if no users exist.

### 6. `forgejo_runner`
* **GitHub Actions Compatibility**: Installs `forgejo-runner` (`v13.2.0`), Docker + Buildx, and Node.js/npm, plus `ghes-preload.cjs` so `actions/upload-artifact@v4` works out-of-the-box.
* **Zero-Touch Registration**: Connects to `[git_servers]`, generates a registration token via `forgejo forgejo-cli actions generate-runner-token`, and registers the runner non-interactively.
* **Systemd Daemon**: Configures and starts `forgejo-runner.service`.

### 7. `restore_backup`
* **Auto-Discovery on Host**: Detects the latest `forgejo-dump-*.zip` in `~/forgejo-backups` on the control machine, or accepts an explicit path via `backup_src`.
* **Integrity Validation & Restore**: Verifies CRC32 checksums, runs `make restore`, regenerates SSH `authorized_keys`, and audits repository/user counts.

---

## Playbooks

| Playbook | Description | Target Hosts |
|---|---|---|
| `playbooks/configure-kvm.yml` | Configures KVM/libvirt host, creates standalone VMs, checks status/overview, and manages snapshots | `localhost` |
| `playbooks/provision-kvm.yml` | Launches KVM VM (`git-server`, `192.168.122.100`) and provisions Forgejo Git Server | `localhost` + `git_servers` |
| `playbooks/provision-runner-kvm.yml` | Launches KVM Runner VM (`git-runner`, `192.168.122.101`) and registers with Forgejo | `localhost` + `git_servers` + `git_runners` |
| `playbooks/site.yml` | Full end-to-end configuration (`git_servers` + `git_runners`) | `git_servers`, `git_runners` |
| `playbooks/deploy-git-server.yml` | Fast update of application stack only (skips OS package steps) | `git_servers` |
| `playbooks/deploy-runner.yml` | Enables Forgejo Actions and provisions/registers runners | `git_servers`, `git_runners` |
| `playbooks/restore.yml` | Transfers and restores host backup archive to target server(s) | `git_servers` |

---

## Quick Start Commands

```bash
# 1. Configure KVM / Libvirt and Remote Management on the Host
make configure_virtualization
make configure_vm_manager

# 2. Launch a KVM Git Server VM ('git-server' at 192.168.122.100) and provision with Ansible
make ansible-kvm-server

# 3. Launch a dedicated KVM Runner VM ('git-runner' at 192.168.122.101) and register with Forgejo
make ansible-kvm-runner

# 4. Inspect KVM VMs and Snapshots
make workspace
make vm_status VM_NAME=git-server
make snapshot VM_NAME=git-server SNAPSHOT_NAME=clean-state
make snapshot_list VM_NAME=git-server

# 5. View Remote KVM Management & SSH ProxyJump Connection Info
make kvm_remote_info
```
