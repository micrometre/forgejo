# Infrastructure as Code (Ansible)

This folder contains a production-ready Ansible automation suite to provision, configure, and manage the Forgejo Git Server across any target environment:
- **Local Multipass VMs** (for development, disaster recovery testing, and staging)
- **Bare-metal servers**
- **Cloud instances** (Hetzner, AWS, DigitalOcean, Linode, etc.)

---

## Directory Structure

```text
ansible/
├── ansible.cfg                    # Preconfigured SSH, pipelining, and inventory settings
├── inventory/
│   ├── hosts.ini                  # Target server definitions and host groups
│   └── group_vars/
│       └── all.yml                # Configurable ports, versions, paths, credentials
├── playbooks/
│   ├── site.yml                   # Master playbook: runs common + docker + git_server
│   ├── deploy-git-server.yml      # Fast app deployment (skips OS packages)
│   ├── provision-multipass.yml    # Turnkey: launches Multipass VM and provisions it
│   └── restore.yml                # Restores host backup archive onto target server(s)
└── roles/
    ├── common/                    # OS baseline: apt cache, essential tools, SSH keys
    ├── docker/                    # Installs Docker CE & Docker Compose plugin
    ├── git_server/                # Templates .env & compose, starts containers, creates admin
    └── restore_backup/            # Auto-locates, transfers, and restores host backup archive
```

---

## Roles Overview

### 1. `common`
* Updates apt package cache.
* Installs baseline utilities (`curl`, `wget`, `git`, `make`, `jq`, `unzip`, `ca-certificates`, `gnupg`, `htop`, `net-tools`).
* Ensures the deployment user exists with passwordless sudo access.
* Sets up user SSH directory and ensures host backup directories exist.

### 2. `docker`
* Installs Docker CE Engine and the official Docker Compose v2 CLI plugin.
* Adds the deploy user to the `docker` group.
* Enables and starts `docker.service` with automatic health checks.

### 3. `git_server`
* Creates application directory structure (`data/forgejo`, `data/postgres`, `make/`, `scripts/`).
* Templates `docker-compose.yml` and `.env` from Jinja2 templates using inventory variables.
* Copies project Makefiles and utility scripts (`verify-backup.sh`, `backup-to-gdrive.sh`).
* Starts containers (`docker compose up -d`) and waits for the HTTP healthcheck on port 3000.
* Queries the database user count and automatically provisions the default administrator account if no users exist.

### 4. `restore_backup`
* **Auto-Discovery on Host**: Detects the latest `forgejo-dump-*.zip` in `~/forgejo-backups` on the control machine, or accepts an explicit path via `backup_src`.
* **Safe Transfer**: Securely transfers the archive to the remote target host.
* **Integrity Validation**: Runs `unzip -tq` to verify archive CRC32 checksums before touching the database.
* **Database & Repository Restore**: Runs `make restore` with non-interactive confirmation.
* **SSH Key Doctor**: Fixes and regenerates Git SSH `authorized_keys`.
* **Post-Restore Audit**: Queries target database to confirm exact repository and user count, reporting a clean summary.

---

## Playbooks

| Playbook | Description | Target Hosts |
|---|---|---|
| `playbooks/site.yml` | Full end-to-end configuration (`common` → `docker` → `git_server`) | `git_servers` |
| `playbooks/deploy-git-server.yml` | Fast update of application stack only (skips OS package steps) | `git_servers` |
| `playbooks/provision-multipass.yml` | Launches a Multipass VM locally and provisions it via Ansible | `localhost` + VM |
| `playbooks/restore.yml` | Transfers and restores host backup archive to target server(s) | `git_servers` |

---

## Quick Start Commands

The root [`Makefile`](../Makefile) includes targets for all common Ansible workflows:

```bash
# 1. Test SSH connectivity across all inventory hosts
make ansible-ping

# 2. Deploy or update the full stack on all inventory servers
make ansible-deploy

# 3. Fast application update (skips OS package installations)
make ansible-app

# 4. Restore newest host backup to all inventory servers (or pass FILE=...)
make ansible-restore
make ansible-restore FILE=/home/ubuntu/forgejo-backups/forgejo-dump-20261014_204642.zip

# 5. Launch a Multipass VM and provision it end-to-end with Ansible
make ansible-vm
```

You can also run playbooks directly using `ansible-playbook`:

```bash
# Full deployment using the local ansible.cfg:
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/site.yml

# Restore backup using dedicated restore playbook:
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/restore.yml \
  -e "backup_src=/home/ubuntu/forgejo-backups/forgejo-dump-20261014_204642.zip"
```

---

## Adding Remote / Production Servers

1. Open [`inventory/hosts.ini`](inventory/hosts.ini) and add your server under `[git_servers]`:
   ```ini
   [git_servers]
   git-vm ansible_host=10.134.198.130 ansible_user=ubuntu
   prod-git ansible_host=192.168.1.100 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519
   ```

2. Customize variables in [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml):
   ```yaml
   forgejo_http_port: 3000
   forgejo_ssh_port: 222
   forgejo_domain: "git.mycompany.local"
   admin_user: "ubuntu"
   admin_password: "ChangeMeInProduction!"
   ```

3. Run `make ansible-deploy` (or limit to a specific host with `EXTRA_VARS="--limit prod-git"`):
   ```bash
   make ansible-deploy EXTRA_VARS="--limit prod-git"
   ```
