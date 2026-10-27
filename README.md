# Forgejo Git Server & Runner (Ansible + KVM / Libvirt)

A self-hosted [Forgejo](https://forgejo.org/) Git server and [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/) CI/CD runner infrastructure managed entirely as **Infrastructure as Code (Ansible)** on **libvirt + KVM** virtual machines (modeled after [`micrometre/ansible-kvm`](https://github.com/micrometre/ansible-kvm)).

| Resource | VM Name | Static IP (`virbr0`) | SSH Shortcut | Details |
|---|---|---|---|---|
| **Git Server** | `git-server` | `192.168.122.100` | `ssh git-server` / `ssh git.server` | Forgejo 16 + PostgreSQL 16 (`http://192.168.122.100:3000`, Git SSH `git@git.vm` port `222`) |
| **Actions Runner** | `git-runner` | `192.168.122.101` | `ssh git.runner` | Forgejo Runner `v13.2.0` + Docker + Buildx + Node.js/dpkg |
| **Backups** | Host & GDrive | `~/forgejo-backups/` | — | Automated via Ansible (`make backup` / `make restore`) + `rclone` offsite sync |

---

## Contents

- [Quick Start](#quick-start)
- [Command Reference](#command-reference)
- [KVM / Libvirt VM & Snapshot Management](#kvm--libvirt-vm--snapshot-management)
- [Accessing & Managing VMs from Another Host](#accessing--managing-vms-from-another-host)
- [GitHub Actions & Forgejo Runner (`git-runner`)](#github-actions--forgejo-runner-git-runner)
- [Working with Repositories](#working-with-repositories)
- [Backup, Verification & Restore](#backup-verification--restore)
- [Offsite Backups (Google Drive)](#offsite-backups-google-drive)
- [Project Layout](#project-layout)

---

## Quick Start

```bash
# 1. Configure KVM/libvirt virtualization and remote access (Cockpit + qemu+ssh) on host
make configure_virtualization
make configure_vm_manager

# 2. Launch the 'git-server' KVM VM (192.168.122.100) and provision Forgejo + PostgreSQL
make ansible-kvm-server

# 3. Launch the 'git-runner' KVM VM (192.168.122.101) and register Forgejo Actions Runner
make ansible-kvm-runner

# 4. Open the Forgejo Web UI
xdg-open http://192.168.122.100:3000
```

All settings (versions, ports, credentials, runner labels) are centrally managed in [`ansible/inventory/group_vars/all.yml`](ansible/inventory/group_vars/all.yml).

---

## Command Reference

Run `make` or `make help` to list all available targets.

### KVM / Libvirt Setup & VM Lifecycle (`make/setup.mk`, `make/vm.mk`, `make/snapshot.mk`)

| Command | Description |
|---|---|
| `make configure_virtualization` | Install and configure KVM, libvirt, Cockpit Web UI (`:9090`), and remote `qemu+ssh` access |
| `make configure_vm_manager` | Configure KVM VM manager workspace (`~/vm-workspace`) and cloud image cache (`~/vm-images`) |
| `make create_vm [VM_NAME=…]` | Create a standalone KVM VM (default `git-server` at `192.168.122.100`) |
| `make vm_status [VM_NAME=…]` | Show detailed status, IP, VNC port, and SSH readiness for a KVM VM |
| `make workspace` | Show KVM VMs overview (`qemu:///system`), disk images, and remote management URLs |
| `make clean_vm [VM_NAME=…]` | Destroy and remove a specific KVM VM and its disk image |
| `make clean_all` | Remove cached VM cloud images and workspace directories (`~/vm-workspace`, `~/vm-images`) |
| `make snapshot` / `make snapshot_create` | Create a snapshot of `VM_NAME` (optional `SNAPSHOT_NAME=…`, `SNAPSHOT_DESC=…`) |
| `make snapshot_list` | List all snapshots for `VM_NAME` |
| `make snapshot_revert SNAPSHOT_NAME=…` | Revert `VM_NAME` to a snapshot |
| `make snapshot_delete SNAPSHOT_NAME=…` | Delete a snapshot from `VM_NAME` |
| `make snapshot_clone SNAPSHOT_NAME=… NEW_VM_NAME=…` | Clone a new KVM VM from an existing snapshot |
| `make kvm_remote_info` | Display connection commands to access & manage KVM VMs from another host |
| `make kvm_port_forward [ACTION=enable\|disable]` | Enable/disable host-to-VM port forwarding (`:3000` & `:222`) for LAN access |

### Ansible Provisioning (`make/ansible.mk`)

| Command | Description |
|---|---|
| `make ansible-ping` | Test SSH connectivity to all inventory servers (`git-server`, `git-runner`) |
| `make ansible-kvm-server` | Create KVM VM (`git-server`, `192.168.122.100`) and provision Forgejo Git Server with Ansible |
| `make ansible-kvm-runner` | Create KVM Runner VM (`git-runner`, `192.168.122.101`) and register it with Forgejo via Ansible |
| `make ansible-deploy` | Run full Ansible site playbook across `[git_servers]` and `[git_runners]` |
| `make ansible-app` | Fast deployment/update of Git Server application stack only (skips OS packages) |
| `make ansible-runner` | Provision and register Forgejo Actions Runner on `[git_runners]` inventory hosts |
| `make ansible-backup` | Create a full Forgejo + PostgreSQL backup on `[git_servers]` and download to `~/forgejo-backups` |
| `make ansible-restore [FILE=…]` | Transfer and restore a host backup archive onto `[git_servers]` |

### Backups & Repository Sync (`make/backup.mk`)

| Command | Description |
|---|---|
| `make backup` | Alias for `make ansible-backup` (writes archive to `~/forgejo-backups/`) |
| `make restore [FILE=…]` | Alias for `make ansible-restore` (restores newest backup or `FILE` to `git-server`) |
| `make check-backup [FILE=…]` | Verify backup ZIP CRC integrity and check repository/database completeness |
| `make backup-gdrive [ARGS=--new]` | Upload the newest backup to Google Drive via `rclone` |
| `make backup-branches [ARGS=…]` | Run `backup_branches.sh` across all repositories in `~/repos` |

*See [`ansible/README.md`](ansible/README.md) for detailed role and playbook documentation.*

---

## KVM / Libvirt VM & Snapshot Management

### Customizing VM Resources or Distribution
Supported cloud-image distributions in [`ansible/roles/vm-manager/defaults/main.yml`](ansible/roles/vm-manager/defaults/main.yml) include `noble` (Ubuntu 24.04 LTS, default), `jammy` (Ubuntu 22.04 LTS), `focal` (Ubuntu 20.04 LTS), `debian12`, and `debian11`:

```bash
make ansible-kvm-server VM_NAME=git-server VM_DISTRO=noble VM_CPUS=4 VM_RAM=8192 VM_DISK=40G VM_IP=192.168.122.100
```

### Snapshots & Cloning
Because KVM VMs use thin-provisioned qcow2 storage in `/var/lib/libvirt/images/`, you can create and revert snapshots instantaneously:

```bash
# Create a snapshot before an upgrade
make snapshot VM_NAME=git-server SNAPSHOT_NAME=before-upgrade SNAPSHOT_DESC="Clean Forgejo 16 state"

# List all snapshots for a VM
make snapshot_list VM_NAME=git-server

# Revert VM to a snapshot
make snapshot_revert VM_NAME=git-server SNAPSHOT_NAME=before-upgrade

# Clone a new VM from an existing snapshot
make snapshot_clone VM_NAME=git-server SNAPSHOT_NAME=before-upgrade NEW_VM_NAME=git-staging

# Delete a snapshot
make snapshot_delete VM_NAME=git-server SNAPSHOT_NAME=before-upgrade
```

---

## Accessing & Managing VMs from Another Host

The `virtualization` role configures your KVM host so you can inspect, start/stop, view consoles, and SSH into VMs from **any other workstation on your network**. Run `make kvm_remote_info` at any time to display your host's exact connection strings.

### 1. Remote Virt-Manager (GUI) & `virsh` (CLI) over SSH
Because your user (`ubuntu`) is a member of the `libvirt` and `kvm` groups and `/etc/libvirt/libvirtd.conf` is configured with `unix_sock_group = "libvirt"`, you can connect `virt-manager` or `virsh` directly from another Linux/macOS computer over SSH:

```bash
# On your remote workstation — open the Virt-Manager GUI connected to the KVM host:
virt-manager -c 'qemu+ssh://ubuntu@<KVM_HOST_IP>/system?socket=/var/run/libvirt/libvirt-sock'

# Or run virsh CLI commands remotely from another computer:
virsh -c 'qemu+ssh://ubuntu@<KVM_HOST_IP>/system' list --all
virsh -c 'qemu+ssh://ubuntu@<KVM_HOST_IP>/system' snapshot-list git-server
```

### 2. Web-Based VM Console & Management (Cockpit Machines)
Cockpit and `cockpit-machines` are installed and enabled on port `9090`. From any browser on another host, open:
- **URL:** `https://<KVM_HOST_IP>:9090`
- Log in with your KVM host Linux credentials (`ubuntu`) and select **Virtual Machines** to start, stop, snapshot, inspect CPU/memory usage, or open an interactive in-browser VNC/serial console for `git-server` and `git-runner`.

### 3. Direct SSH & Git Access to VMs from Another Host (`ProxyJump`)
To SSH directly into `git-server` (`192.168.122.100`) or `git-runner` (`192.168.122.101`), or push/pull Git repositories from another laptop/workstation without extra network routing, add `ProxyJump` to `~/.ssh/config` on your **remote client machine**:

```sshconfig
# ~/.ssh/config on your remote laptop / workstation
Host kvm-host
    HostName <KVM_HOST_IP>
    User ubuntu

Host git-server
    HostName 192.168.122.100
    User ubuntu
    ProxyJump kvm-host
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host git-runner
    HostName 192.168.122.101
    User ubuntu
    ProxyJump kvm-host
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host git.vm
    HostName 192.168.122.100
    Port 222
    User git
    ProxyJump kvm-host
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

### 4. Exposing Forgejo (`:3000` & `:222`) to the LAN (`make kvm_port_forward`)
If you want other machines on your LAN to access Forgejo's Web UI (`http://<KVM_HOST_IP>:3000`) and Git SSH (`ssh://git@<KVM_HOST_IP>:222`) directly via the KVM host's IP address:

```bash
# Enable iptables DNAT port forwarding from KVM Host (:3000, :222) -> git-server VM (192.168.122.100)
make kvm_port_forward ACTION=enable

# Disable port forwarding when no longer needed
make kvm_port_forward ACTION=disable
```

Alternatively, on another Linux workstation on the same LAN, you can add a static route to the KVM subnet:
```bash
sudo ip route add 192.168.122.0/24 via <KVM_HOST_IP>
```

---

## GitHub Actions & Forgejo Runner (`git-runner`)

Forgejo includes built-in **Forgejo Actions**, which is compatible with standard **GitHub Actions** workflows (`.github/workflows/*.yml` or `.forgejo/workflows/*.yml`).

### Provisioning the KVM Runner VM
```bash
make ansible-kvm-runner
```

What this does automatically:
1. Launches the `git-runner` KVM VM (`192.168.122.101`, Ubuntu 24.04 LTS, 4 vCPUs, 4GB RAM, 60GB qcow2 disk).
2. Injects your host SSH keys and configures `Host git.runner` in `~/.ssh/config` and `git-runner` under `[git_runners]` in [`ansible/inventory/hosts.ini`](ansible/inventory/hosts.ini).
3. Installs Docker Engine, Docker Compose v2, Docker Buildx, Node.js/npm, and Debian packaging tools (`dpkg-dev`, `fakeroot`, etc.).
4. Downloads `/usr/local/bin/forgejo-runner` (`v13.2.0`), deploys `ghes-preload.cjs` (so `actions/upload-artifact@v4` works seamlessly), fetches a registration token from `git-server`, and registers the runner non-interactively.
5. Starts and enables the `forgejo-runner.service` systemd daemon.

### Runner Labels

| Workflow `runs-on:` | Runner Label Mapping | Execution Environment |
|---|---|---|
| `ubuntu-latest` | `ubuntu-latest:host` | Runs directly on the dedicated `git-runner` Ubuntu 24.04 KVM VM |
| `ubuntu-24.04` | `ubuntu-24.04:host` | Runs directly on the dedicated `git-runner` Ubuntu 24.04 KVM VM |
| `ubuntu-22.04` | `ubuntu-22.04:host` | Runs directly on the dedicated `git-runner` Ubuntu 24.04 KVM VM |
| `self-hosted` | `self-hosted:host` | Runs directly on the dedicated `git-runner` Ubuntu 24.04 KVM VM |
| `docker` | `docker:docker://node:20-bookworm` | Runs inside an isolated `node:20-bookworm` Docker container |

### Monitoring the Runner
```bash
ssh git.runner "systemctl status forgejo-runner"
ssh git.runner "journalctl -u forgejo-runner -f"
```

---

## Working with Repositories

When `make ansible-kvm-server` runs, it automatically configures `Host git.vm` in `~/.ssh/config` pointing to `192.168.122.100:222`:

```bash
# Clone via SSH alias
git clone git@git.vm:ubuntu/my-repo.git

# Clone via HTTP
git clone http://192.168.122.100:3000/ubuntu/my-repo.git

# Sync all repository branches in ~/repos to Forgejo
make backup-branches
```

---

## Backup, Verification & Restore

```bash
# 1. Create a full backup on git-server via Ansible and download to ~/forgejo-backups/
make backup

# 2. Verify archive integrity (CRC32, SQL dump, app.ini, and bare Git repositories)
make check-backup

# 3. Restore the latest backup (or a specific FILE=...) onto git-server via Ansible
make restore
make restore FILE=~/forgejo-backups/forgejo-dump-20261027_175619.zip
```

---

## Offsite Backups (Google Drive)

```bash
make backup-gdrive                 # Upload the newest backup in ~/forgejo-backups to Google Drive
make backup-gdrive ARGS=--new      # Run 'make backup' via Ansible first, then upload to Google Drive
```

---

## Project Layout

```text
.
├── .github/workflows/
│   └── ci.yml                      # Sample GitHub Actions CI workflow
├── Makefile                        # Main orchestrator (includes make/*.mk)
├── make/                           # Modular makefiles (matching ansible-kvm structure)
│   ├── config.mk                   # Default variables and help target
│   ├── setup.mk                    # Host KVM/libvirt & remote management setup
│   ├── vm.mk                       # KVM VM creation, status, workspace, and cleanup
│   ├── snapshot.mk                 # KVM VM snapshot management (create, list, revert, clone)
│   ├── ansible.mk                  # Ansible IaC deployment targets
│   └── backup.mk                   # Ansible-driven backup, verification, restore, and sync
├── ansible/                        # Infrastructure as Code
│   ├── ansible.cfg                 # Ansible configuration
│   ├── inventory/                  # Hosts inventory ([git_servers], [git_runners]) and group_vars
│   ├── playbooks/                  # site, configure-kvm, provision-kvm, provision-runner-kvm, backup, restore
│   └── roles/                      # virtualization, vm-manager, common, docker, git_server, forgejo_runner, restore_backup
└── scripts/
    ├── backup-all-branches.sh      # Syncs all repository branches in ~/repos to Forgejo
    ├── backup-to-gdrive.sh         # rclone upload to Google Drive
    ├── verify-backup.sh            # Archive integrity and completeness verification
    └── kvm-remote-access.sh        # Remote KVM access & host-to-VM port forwarding helper
```
