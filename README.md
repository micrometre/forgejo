# Forgejo Git Server

A self-hosted [Forgejo](https://forgejo.org/) Git server running on Docker Compose with PostgreSQL. A `Makefile` handles the day-to-day work: starting and stopping, managing users, backups, restores and offsite copies to Google Drive.

Based on the official [Forgejo Docker installation guide](https://forgejo.org/docs/latest/admin/installation/docker/).

| | |
|---|---|
| **Web UI** | <http://localhost:3000> |
| **SSH clone** | `ssh://git@localhost:222/<owner>/<repo>.git` |
| **Stack** | Forgejo 16 + PostgreSQL 16 (Alpine) |
| **Data** | `./data/` (bind mounts) |
| **Backups** | `~/forgejo-backups/` (optionally copied to Google Drive) |

---

## Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Command Reference](#command-reference)
- [Configuration](#configuration)
- [Working with Repositories](#working-with-repositories)
- [Backup & Restore](#backup--restore)
- [Offsite Backups (Google Drive)](#offsite-backups-google-drive)
- [Upgrading Forgejo](#upgrading-forgejo)
- [Security Checklist](#security-checklist)
- [Troubleshooting](#troubleshooting)
- [Project Layout](#project-layout)

---

## Prerequisites

- Docker Engine with the Compose v2 plugin (`docker compose version`)
- `make`, `zip`, `unzip`
- `rclone`, only needed for [offsite backups](#offsite-backups-google-drive)
- Your host user should be UID/GID `1000`. Check with `id`. If yours differs, change `USER_UID`/`USER_GID` in `.env`.

---

## Quick Start

```bash
# 1. Start Forgejo + PostgreSQL (creates .env and ./data on first run)
make up

# 2. Create your admin account
make create-admin ADMIN_USER=ubuntu ADMIN_PASS='choose-a-strong-password' ADMIN_EMAIL=you@example.com

# 3. Open the web UI and sign in
xdg-open http://localhost:3000
```

> [!NOTE]
> `FORGEJO__security__INSTALL_LOCK=true` is set in `docker-compose.yml`, so the web install wizard is skipped and the instance is ready right away. You must create the first admin from the CLI as shown above.

> [!IMPORTANT]
> `admin` is a **reserved username** in Forgejo (it clashes with the `/admin` route), so pick a different name.

If you leave out the arguments, `make create-admin` uses `ubuntu` / `admin-1234` / `admin@example.local`. Only use those defaults for local testing.

---

## Command Reference

Run `make` or `make help` to list every target.

### Lifecycle

| Command | Description |
|---|---|
| `make up` | Start all services in the background |
| `make down` | Stop and remove containers (keeps your data) |
| `make restart` | Restart all services |
| `make status` / `make ps` | Show container status and health |
| `make pull` | Pull newer images (then run `make up` to apply them) |
| `make shell` | Open a shell inside the Forgejo container |

### Logs

| Command | Description |
|---|---|
| `make logs` | Follow logs from all services |
| `make logs-server` | Follow Forgejo logs |
| `make logs-db` | Follow PostgreSQL logs |

### Users

| Command | Description |
|---|---|
| `make create-admin ADMIN_USER=… ADMIN_PASS=… ADMIN_EMAIL=…` | Create an administrator |
| `make reset-password USER=… PASS=…` | Reset a user's password and clear the "must change password" flag |

### Data

| Command | Description |
|---|---|
| `make backup` | Write a full backup to `$BACKUP_DIR` |
| `make check-backup [FILE=…]` | Verify archive integrity and check repository/database completeness |
| `make restore [FILE=…]` | Restore from the newest backup, or from `FILE` |
| `make backup-gdrive [ARGS=--new]` | Upload the newest backup to Google Drive |
| `make clean` | **Destructive.** Remove containers and `./data` (asks for confirmation; backups are kept) |

### Testing & VM (Multipass)

| Command | Description |
|---|---|
| `make provision-vm [VM_NAME=…]` | Launch and provision a fresh Multipass VM with Git server running |
| `make vm-restore [FILE=…]` | Provision VM and test-restore a backup archive |
| `make vm-status` | List running Multipass VMs |
| `make vm-shell` | Shell into the test VM |
| `make vm-clean` | Stop and delete the test VM |

### Infrastructure as Code (Ansible)

| Command | Description |
|---|---|
| `make ansible-ping` | Test SSH connectivity to all inventory servers |
| `make ansible-deploy` | Run end-to-end site playbook on inventory hosts (`common` + `docker` + `git_server`) |
| `make ansible-app` | Fast deployment/update of Git server stack only (skips OS packages) |
| `make ansible-vm` | Launch Multipass VM and provision completely with Ansible |

---

## Configuration

All settings live in `.env`, which is created from `.env.example` on first run and kept out of git.

| Variable | Default | Purpose |
|---|---|---|
| `FORGEJO_VERSION` | `16` | Forgejo image tag |
| `FORGEJO_HTTP_PORT` | `3000` | Host port for the web UI |
| `FORGEJO_SSH_PORT` | `222` | Host port for Git over SSH (also used in clone URLs) |
| `USER_UID` / `USER_GID` | `1000` | Owner of files in `./data/forgejo` |
| `FORGEJO_DOMAIN` | `localhost` | Hostname used in clone URLs |
| `FORGEJO_ROOT_URL` | `http://localhost:3000/` | Public base URL |
| `POSTGRES_VERSION` | `16-alpine` | PostgreSQL image tag |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | `forgejo` | Database credentials |
| `BACKUP_DIR` | `/home/ubuntu/forgejo-backups` | Where backups are written and read |
| `RCLONE_REMOTE` | `gdrive:Forgejo-Backups` | rclone destination for offsite backups |

Run `make up` after editing `.env` so the containers pick up the changes.

### Changing other Forgejo settings

You can set any [`app.ini` option](https://forgejo.org/docs/latest/admin/config-cheat-sheet/) as an environment variable named `FORGEJO__<SECTION>__<KEY>`. Add it under `server.environment` in `docker-compose.yml`:

```yaml
- FORGEJO__service__DISABLE_REGISTRATION=true   # stop public sign-ups
- FORGEJO__service__REQUIRE_SIGNIN_VIEW=true    # hide everything from anonymous users
- FORGEJO____APP_NAME=My Company Git            # keys in the top-level section use an empty section name
```

---

## Working with Repositories

### Cloning

```bash
# SSH (add your public key under User Settings → SSH / GPG Keys first)
git clone ssh://git@localhost:222/ubuntu/my-repo.git

# HTTP
git clone http://localhost:3000/ubuntu/my-repo.git
```

To avoid typing the port each time, add this to `~/.ssh/config`:

```sshconfig
Host forgejo
    HostName localhost
    Port 222
    User git
```

Then clone with `git clone forgejo:ubuntu/my-repo.git`. *(If testing in a Multipass VM, see [Multipass SSH Configuration](#ssh-configuration-sshconfig)).*

### Pushing an existing project

```bash
cd ~/repos/my-project
git remote add forgejo ssh://git@localhost:222/ubuntu/my-project.git
git push -u forgejo --all && git push forgejo --tags
```

### Where the repository files are stored

Repositories are kept as **bare Git repositories**. They contain Git objects, not checked-out source files:

```
./data/forgejo/git/repositories/<owner>/<repo>.git/
```

To read code without cloning:

```bash
REPO=data/forgejo/git/repositories/ubuntu/my-repo.git
git --git-dir=$REPO ls-tree -r HEAD --name-only        # list files
git --git-dir=$REPO show HEAD:README.md                # print one file
mkdir -p /tmp/export && git --git-dir=$REPO archive HEAD | tar -x -C /tmp/export
```

> [!WARNING]
> Don't edit files under `./data/forgejo/git/` directly. Use `git push` or the web UI so Forgejo's database stays in sync.

---

## Backup & Restore

### Creating a backup

```bash
make backup
```

This writes `$BACKUP_DIR/forgejo-dump-YYYYMMDD_HHMMSS.zip`, which contains:

| Path in archive | Contents |
|---|---|
| `forgejo-postgres.sql` | Native `pg_dump` of the database. The restore uses this file. |
| `forgejo-db.sql` | Forgejo's own SQL export, used only as a fallback |
| `repos/` | All bare Git repositories |
| `data/` | `app.ini`, avatars, attachments, indexes, JWT keys, etc. |

You can make backups while the server is running.

### Verifying a backup

You can verify that a backup archive is valid, uncorrupted, and contains all repositories, configuration, and database tables:

```bash
make check-backup                                                   # audits newest backup in $BACKUP_DIR
make check-backup FILE=~/forgejo-backups/forgejo-dump-20261014_192429.zip
```

The verification script checks:
1. **Archive integrity**: runs `unzip -t` to test CRC32 checksums of every compressed file.
2. **Core components**: confirms PostgreSQL database dump (`forgejo-postgres.sql`), `app.ini`, and data directories exist and are non-empty.
3. **Git repositories**: unpacks repository inventory and displays all bare Git projects.
4. **Live server parity**: if Forgejo and PostgreSQL are running, it queries the live PostgreSQL database and compares repository and user counts directly against the backup.

### Restoring

```bash
make restore                                                   # newest file in $BACKUP_DIR
make restore FILE=~/forgejo-backups/forgejo-dump-20261013_140909.zip
```

The restore:

1. Starts PostgreSQL and waits until it is ready
2. Stops Forgejo
3. Drops and recreates the database schema, then imports the SQL dump
4. Replaces repositories and application data, and resets file ownership to `1000:1000`
5. Starts Forgejo and regenerates SSH `authorized_keys`

> [!CAUTION]
> A restore **overwrites** the current database and repositories. Anything created after the backup was taken is lost.

### Rebuilding from scratch

`make clean` never touches `$BACKUP_DIR`, so you can rebuild the whole instance from a backup:

```bash
make clean      # wipe containers and ./data
make restore    # rebuild from the newest backup
```

This also works for moving to a new machine: copy the repo and a backup ZIP across, then run `make restore FILE=…`.

---

## Offsite Backups (Google Drive)

[`scripts/backup-to-gdrive.sh`](scripts/backup-to-gdrive.sh) uses an existing rclone remote (`gdrive:` by default) to upload backups.

```bash
make backup-gdrive                         # upload the newest backup
make backup-gdrive ARGS=--new              # take a fresh backup, then upload it

./scripts/backup-to-gdrive.sh --all        # copy every backup (rclone skips files already uploaded)
./scripts/backup-to-gdrive.sh <file.zip>   # upload one specific file
./scripts/backup-to-gdrive.sh --help
```

Check that the remote works before you rely on it:

```bash
rclone lsd gdrive:
rclone ls gdrive:Forgejo-Backups
```

### Getting a backup back from Google Drive

```bash
rclone copy gdrive:Forgejo-Backups/forgejo-dump-20261013_140909.zip ~/forgejo-backups/
make restore FILE=~/forgejo-backups/forgejo-dump-20261013_140909.zip
```

### Scheduling backups

Add a nightly backup and upload to your crontab with `crontab -e`:

```cron
# Every day at 02:30: back up Forgejo and upload to Google Drive
30 2 * * * cd /home/ubuntu/repos/git-server && ./scripts/backup-to-gdrive.sh --new >> /home/ubuntu/forgejo-backups/cron.log 2>&1
```

To delete local backups older than 14 days, add:

```cron
0 3 * * * find /home/ubuntu/forgejo-backups -name 'forgejo-dump-*.zip' -mtime +14 -delete
```

---

## Upgrading Forgejo

```bash
make backup-gdrive ARGS=--new   # always take a backup first
# Optionally set FORGEJO_VERSION in .env to a newer major version
make pull
make up
make logs-server                # watch the database migrations finish
```

Database migrations run automatically on startup. Before a **major** version upgrade, read the [release notes](https://forgejo.org/releases/) and the [upgrade guide](https://forgejo.org/docs/latest/admin/upgrade/). Forgejo cannot be downgraded, so the only way back is to restore the backup you took.

---

## Security Checklist

The defaults are meant for local use. Before exposing the server to a network:

- [ ] Set a strong `POSTGRES_PASSWORD` in `.env` **before first start**. Changing it later also requires changing it inside PostgreSQL.
- [ ] Create admins with strong passwords, not the `make create-admin` defaults
- [ ] Turn on 2FA for admin accounts (User Settings → Security)
- [ ] Set `FORGEJO__service__DISABLE_REGISTRATION=true` unless you want public sign-ups
- [ ] Put a reverse proxy with TLS in front of the server (Caddy, nginx, Traefik) and update `FORGEJO_DOMAIN` / `FORGEJO_ROOT_URL`
- [ ] Keep backup files private. They contain password hashes and secrets (`chmod 600` is applied by default)
- [ ] Never commit `.env` or `data/` (both are in `.gitignore`)

---

## Troubleshooting

<details>
<summary><b>"Username or password is incorrect"</b></summary>

Reset the password, which also clears the "must change password" flag:

```bash
make reset-password USER=ubuntu PASS='new-password'
```

List the existing accounts:

```bash
docker compose exec --user git server forgejo admin user list
```
</details>

<details>
<summary><b><code>name is reserved [name: admin]</code></b></summary>

`admin` can't be used as a username. Choose another, for example `make create-admin ADMIN_USER=gitadmin …`.
</details>

<details>
<summary><b><code>Unable to load config file for a installed Forgejo instance</code></b></summary>

The instance is not marked as installed. Check that `FORGEJO__security__INSTALL_LOCK=true` is in `docker-compose.yml`, then run `make up` so the container is recreated.
</details>

<details>
<summary><b><code>Permission denied</code> under <code>./data</code></b></summary>

Files are owned by container users (`git` = 1000, `postgres` = 70, and `root` for SSH host keys). Fix ownership with a throwaway container:

```bash
docker run --rm -v "$PWD/data/forgejo:/data" alpine chown -R 1000:1000 /data
make restart
```

`make clean` uses the same approach, so it never needs `sudo`.
</details>

<details>
<summary><b>Container keeps restarting</b></summary>

```bash
make logs-server
docker compose exec --user git server forgejo doctor check --all
```

To fix SSH key problems:

```bash
docker compose exec --user git server forgejo doctor check --run authorized-keys --fix
```
</details>

<details>
<summary><b>Port 3000 or 222 is already in use</b></summary>

Change `FORGEJO_HTTP_PORT` / `FORGEJO_SSH_PORT` in `.env` and run `make up`. If you change the HTTP port, update `FORGEJO_ROOT_URL` as well.
</details>

---

## Testing & Deploying in a Multipass VM

You can spin up an isolated Ubuntu VM using [Multipass](https://multipass.run/) to test the Git server, verify backups, or stage changes without touching your host Docker setup.

### Prerequisites

Multipass must be installed on your machine:
```bash
# Ubuntu / Debian
sudo snap install multipass

# macOS
brew install --cask multipass

# Windows
winget install Canonical.Multipass
```

### Quick Deploy

```bash
make provision-vm
```

This single command:
1. Launches an Ubuntu 24.04 (Noble) VM (`git-server`) with 2 CPUs, 4GB RAM, and 20GB disk.
2. Injects your host SSH public keys (`~/.ssh/*.pub`) for passwordless access.
3. Installs Docker and Docker Compose inside the VM.
4. Packages and transfers this repository to `/home/ubuntu/git-server` inside the VM.
5. Auto-configures `.env` with the VM's assigned IP address so web & Git clone URLs work immediately.
6. Starts Forgejo and PostgreSQL and waits for the health check to pass.

You can customize specs by passing variables:
```bash
make provision-vm VM_NAME=git-test VM_CPUS=4 VM_MEM=8G VM_DISK=30G
```

### Testing Backup Restoration in a VM

To verify disaster recovery and prove that a backup restores cleanly in an isolated environment:

```bash
make vm-restore                                 # tests newest backup in ~/forgejo-backups
make vm-restore FILE=~/forgejo-backups/forgejo-dump-20261014_192429.zip
```

### Accessing the VM

Once deployed, the terminal outputs the VM's access points:
- **Web UI:** `http://<VM-IP>:3000`
- **Git clone:** `git clone ssh://git@<VM-IP>:222/ubuntu/my-repo.git`
- **SSH into VM:** `make vm-shell` or `multipass shell git-server`

### SSH Configuration (`~/.ssh/config`)

To easily connect to the VM OS or clone repositories via SSH without repeatedly typing IP addresses, ports, or passwords, add the following to `~/.ssh/config`:

```sshconfig
# 1. Direct SSH Shell into the Multipass VM OS
Host git-vm
    HostName 10.134.198.130                  # Or git-server.local, or IP from `make vm-status`
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519            # Your host private key (public key is auto-injected by provision-vm)
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# 2. Git over SSH to Forgejo inside the Multipass VM
Host forgejo-vm
    HostName 10.134.198.130                  # Or git-server.local, or IP from `make vm-status`
    Port 222
    User git
    IdentityFile ~/.ssh/id_ed25519            # Key registered in Forgejo Web UI (Settings → SSH / GPG Keys)
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

> [!TIP]
> Setting `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null` avoids host key mismatch warnings whenever test VMs are deleted and recreated.

With this in place:
```bash
# SSH directly into the VM OS:
ssh git-vm

# Clone a repository from Forgejo inside the VM:
git clone forgejo-vm:ubuntu/my-repo.git

# Add the VM Forgejo as a remote to an existing project:
git remote add vm forgejo-vm:ubuntu/my-project.git
git push vm main
```

### Teardown

When you are finished testing:
```bash
make vm-clean
```

---

## Infrastructure as Code (Ansible)

This repository includes a production-ready Ansible suite to provision any target machine (bare metal, cloud VM, or Multipass test instance) from scratch:

```
ansible/
├── ansible.cfg                    # Preconfigured SSH, pipelining, and inventory settings
├── inventory/
│   ├── hosts.ini                  # Target server hosts and groups
│   └── group_vars/
│       └── all.yml                # Configurable ports, versions, paths, credentials
├── playbooks/
│   ├── site.yml                   # Master playbook: runs common + docker + git_server
│   ├── deploy-git-server.yml      # Fast app deployment (skips OS packages)
│   └── provision-multipass.yml    # Turnkey: launches Multipass VM and provisions it
└── roles/
    ├── common/                    # OS baseline: apt cache, essential tools, SSH keys
    ├── docker/                    # Installs Docker CE & Docker Compose plugin
    └── git_server/                # Templates .env & compose, starts containers, creates admin
```

### Quick Commands

```bash
# 1. Test SSH connectivity to all configured hosts:
make ansible-ping

# 2. Deploy or update the full stack on all inventory servers:
make ansible-deploy

# 3. Launch a Multipass VM and provision it end-to-end with Ansible:
make ansible-vm

# 4. Update the Git server application stack only (skipping OS package steps):
make ansible-app
```

### Deploying to Remote Servers

1. Add your server to `ansible/inventory/hosts.ini`:
   ```ini
   [git_servers]
   prod-git ansible_host=192.168.1.100 ansible_user=ubuntu
   ```
2. Adjust environment settings in `ansible/inventory/group_vars/all.yml` if needed.
3. Run `make ansible-deploy`.

---

## Project Layout

```
.
├── docker-compose.yml          # Forgejo + PostgreSQL services
├── Makefile                    # Main orchestrator (includes make/*.mk)
├── make/                       # Modular makefiles
│   ├── config.mk               # Environment, defaults, and help target
│   ├── service.mk              # Service lifecycle (up, down, logs, shell)
│   ├── admin.mk                # User and password management
│   ├── backup.mk               # Backup, verification, restore, and cleanup
│   ├── multipass.mk            # Multipass VM testing and provisioning
│   └── ansible.mk              # Ansible IaC commands
├── ansible/                    # Infrastructure as Code
│   ├── ansible.cfg             # Ansible configuration
│   ├── inventory/              # Hosts inventory and variable definitions
│   ├── playbooks/              # Site, deploy, and multipass playbooks
│   └── roles/                  # common, docker, and git_server roles
├── .env.example                # Configuration template (committed)
├── .env                        # Local configuration (gitignored)
├── scripts/
│   ├── backup-to-gdrive.sh     # rclone upload to Google Drive
│   ├── verify-backup.sh        # Archive integrity and completeness verification
│   └── provision-vm.sh         # Multipass VM launch and provisioning script
├── multipass/
│   └── cloud-init.yaml         # Cloud-init config for Multipass VM
└── data/                       # Persistent state (gitignored)
    ├── forgejo/
    │   ├── git/repositories/   # Bare Git repositories
    │   ├── gitea/              # app.ini, avatars, attachments, indexes, logs
    │   └── ssh/                # SSH host keys
    └── postgres/               # PostgreSQL data files

~/forgejo-backups/              # Backup archives (outside the repo)
```

---

### Using SQLite instead of PostgreSQL

For a single-container setup, remove the `db` service, the `depends_on` block and every `FORGEJO__database__*` variable from `docker-compose.yml`. Forgejo then stores its data in `./data/forgejo/gitea/gitea.db`.

> [!WARNING]
> `make backup` and `make restore` assume PostgreSQL and would need changes to work with SQLite.
