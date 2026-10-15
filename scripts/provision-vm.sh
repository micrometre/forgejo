#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Provision Forgejo Git Server into a Multipass VM
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="${VM_NAME:-git-server}"
VM_CPUS="${VM_CPUS:-2}"
VM_MEM="${VM_MEM:-4G}"
VM_DISK="${VM_DISK:-20G}"
VM_IMAGE="${VM_IMAGE:-noble}"
RESTORE_BACKUP=""
RECREATE="false"

usage() {
    cat <<EOF
Usage: $0 [options]

Provision and deploy Forgejo Git Server inside a Multipass VM.

Options:
  --name <name>       VM name (default: git-server)
  --cpus <count>      Number of CPUs (default: 2)
  --memory <size>     Memory size, e.g. 4G, 8G (default: 4G)
  --disk <size>       Disk size, e.g. 20G (default: 20G)
  --image <distro>    Ubuntu release (default: noble / 24.04 LTS)
  --restore [file]    Restore existing backup into VM (defaults to latest backup)
  --recreate          Delete existing VM first and provision from scratch
  -h, --help          Show this help message

Examples:
  $0
  $0 --name git-test --cpus 4 --memory 8G
  $0 --restore
  $0 --restore ~/forgejo-backups/forgejo-dump-20261014_192429.zip
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --cpus)
            VM_CPUS="$2"
            shift 2
            ;;
        --memory|--mem)
            VM_MEM="$2"
            shift 2
            ;;
        --disk)
            VM_DISK="$2"
            shift 2
            ;;
        --image)
            VM_IMAGE="$2"
            shift 2
            ;;
        --restore)
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                RESTORE_BACKUP="$2"
                shift 2
            else
                RESTORE_BACKUP="latest"
                shift 1
            fi
            ;;
        --recreate)
            RECREATE="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# 1. Verify Multipass is installed
if ! command -v multipass >/dev/null 2>&1; then
    echo "Error: 'multipass' CLI is not found on your host machine." >&2
    echo "" >&2
    echo "To install Multipass:" >&2
    echo "  - Ubuntu / Linux: sudo snap install multipass" >&2
    echo "  - macOS:          brew install --cask multipass" >&2
    echo "  - Windows:        winget install Canonical.Multipass" >&2
    exit 1
fi

echo "================================================================="
echo "  Provisioning Git Server into Multipass VM: ${VM_NAME}"
echo "================================================================="

# 2. Handle Recreate if requested
if [ "${RECREATE}" = "true" ]; then
    if multipass info "${VM_NAME}" >/dev/null 2>&1; then
        echo "--> Deleting existing VM '${VM_NAME}' (--recreate)..."
        multipass delete --purge "${VM_NAME}"
    fi
fi

# 3. Launch or Start VM
CLOUD_INIT="${SCRIPT_DIR}/multipass/cloud-init.yaml"
if ! multipass info "${VM_NAME}" >/dev/null 2>&1; then
    echo "--> Launching new VM '${VM_NAME}' (${VM_IMAGE}, ${VM_CPUS} CPUs, ${VM_MEM} RAM, ${VM_DISK} disk)..."
    if [ -f "${CLOUD_INIT}" ]; then
        multipass launch "${VM_IMAGE}" --name "${VM_NAME}" \
            --cpus "${VM_CPUS}" --memory "${VM_MEM}" --disk "${VM_DISK}" \
            --cloud-init "${CLOUD_INIT}"
    else
        multipass launch "${VM_IMAGE}" --name "${VM_NAME}" \
            --cpus "${VM_CPUS}" --memory "${VM_MEM}" --disk "${VM_DISK}"
    fi
else
    VM_STATE="$(multipass info "${VM_NAME}" | awk '/State:/ {print $2}')"
    if [ "${VM_STATE}" != "Running" ]; then
        echo "--> Starting existing VM '${VM_NAME}' (current state: ${VM_STATE})..."
        multipass start "${VM_NAME}"
    else
        echo "--> VM '${VM_NAME}' is already running."
    fi
fi

# 4. Inject Host SSH Keys if available
if ls "${HOME}"/.ssh/*.pub >/dev/null 2>&1; then
    echo "--> Injecting host SSH public keys into VM..."
    multipass exec "${VM_NAME}" -- mkdir -p .ssh
    multipass exec "${VM_NAME}" -- chmod 700 .ssh
    cat "${HOME}"/.ssh/*.pub | multipass exec "${VM_NAME}" -- tee -a .ssh/authorized_keys >/dev/null
    multipass exec "${VM_NAME}" -- chmod 600 .ssh/authorized_keys
fi

# 5. Ensure Docker & Docker Compose are installed in the VM
echo "--> Verifying Docker environment inside VM..."
multipass exec "${VM_NAME}" -- sudo bash -c '
    set -e
    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        echo "Installing Docker and utilities inside VM..."
        apt-get update -qq
        apt-get install -y -qq docker.io docker-compose-v2 make git curl jq unzip
        systemctl enable --now docker
        usermod -aG docker ubuntu
    fi
    mkdir -p /home/ubuntu/forgejo-backups
    chown -R ubuntu:ubuntu /home/ubuntu
'

# 6. Package and Transfer git-server repository into VM
echo "--> Packaging and transferring git-server files to VM..."
if multipass exec "${VM_NAME}" -- test -f /home/ubuntu/git-server/docker-compose.yml 2>/dev/null; then
    echo "--> Stopping existing containers before updating files..."
    multipass exec "${VM_NAME}" -- sudo -u ubuntu bash -c "cd /home/ubuntu/git-server && docker compose down" >/dev/null 2>&1 || true
fi
multipass exec "${VM_NAME}" -- rm -rf /home/ubuntu/git-server
multipass exec "${VM_NAME}" -- mkdir -p /home/ubuntu/git-server
tar -czf - \
    --exclude='.git' \
    --exclude='data' \
    --exclude='backups' \
    --exclude='*.zip' \
    --exclude='.env' \
    -C "${SCRIPT_DIR}" . | multipass exec "${VM_NAME}" -- tar -xzf - -C /home/ubuntu/git-server
multipass exec "${VM_NAME}" -- chown -R ubuntu:ubuntu /home/ubuntu/git-server

# 7. Configure .env with VM's IPv4 address
VM_IP="$(multipass info "${VM_NAME}" | awk '/IPv4:/ {print $2}' | head -n1)"
if [ -z "${VM_IP}" ]; then
    echo "Warning: Could not automatically detect VM IPv4 address; using localhost"
    VM_IP="localhost"
fi

echo "--> Configuring environment inside VM (VM IP: ${VM_IP})..."
multipass exec "${VM_NAME}" -- sudo -u ubuntu bash -c "
    cd /home/ubuntu/git-server
    cp .env.example .env
    # Update domain and root URL to match the VM IP
    sed -i 's|^FORGEJO_DOMAIN=.*|FORGEJO_DOMAIN=${VM_IP}|' .env
    sed -i 's|^FORGEJO_ROOT_URL=.*|FORGEJO_ROOT_URL=http://${VM_IP}:3000/|' .env
    sed -i 's|^BACKUP_DIR=.*|BACKUP_DIR=/home/ubuntu/forgejo-backups|' .env
"

# 8. Deploy / Restore Git Server
if [ -n "${RESTORE_BACKUP}" ]; then
    # Resolve backup file
    if [ "${RESTORE_BACKUP}" = "latest" ]; then
        HOST_BACKUP="$(ls -t "${HOME}"/forgejo-backups/forgejo-dump-*.zip 2>/dev/null | head -n1 || true)"
        if [ -z "${HOST_BACKUP}" ]; then
            HOST_BACKUP="$(ls -t "${SCRIPT_DIR}"/backups/forgejo-dump-*.zip 2>/dev/null | head -n1 || true)"
        fi
    else
        HOST_BACKUP="${RESTORE_BACKUP}"
    fi

    if [ -n "${HOST_BACKUP}" ] && [ -f "${HOST_BACKUP}" ]; then
        echo "--> Transferring backup to VM for restore test (${HOST_BACKUP})..."
        multipass exec "${VM_NAME}" -- mkdir -p /home/ubuntu/forgejo-backups
        if [[ "${HOST_BACKUP}" != "${HOME}"* ]]; then
            TMP_BKP="${HOME}/.cache/forgejo-restore-temp.zip"
            mkdir -p "${HOME}/.cache"
            cp "${HOST_BACKUP}" "${TMP_BKP}"
            multipass transfer "${TMP_BKP}" "${VM_NAME}:/home/ubuntu/forgejo-backups/restore-target.zip"
            rm -f "${TMP_BKP}"
        else
            multipass transfer "${HOST_BACKUP}" "${VM_NAME}:/home/ubuntu/forgejo-backups/restore-target.zip"
        fi
        echo "--> Running restore inside VM..."
        multipass exec "${VM_NAME}" -- sudo -u ubuntu bash -c "
            cd /home/ubuntu/git-server
            make restore FILE=/home/ubuntu/forgejo-backups/restore-target.zip CONFIRM=y
        "
    else
        echo "Warning: Backup file '${RESTORE_BACKUP}' not found. Starting fresh git-server instead."
        multipass exec "${VM_NAME}" -- sudo -u ubuntu bash -c "cd /home/ubuntu/git-server && make up"
    fi
else
    echo "--> Starting Forgejo and PostgreSQL inside VM..."
    multipass exec "${VM_NAME}" -- sudo -u ubuntu bash -c "cd /home/ubuntu/git-server && make up"
fi

# 9. Health Check
echo -n "--> Waiting for Forgejo service to become ready..."
READY=false
for i in {1..30}; do
    if multipass exec "${VM_NAME}" -- curl -s -f -o /dev/null "http://localhost:3000/" 2>/dev/null || \
       curl -s -f -o /dev/null "http://${VM_IP}:3000/" 2>/dev/null; then
        READY=true
        break
    fi
    sleep 2
    echo -n "."
done
echo ""

if [ "${READY}" = "true" ]; then
    echo "✅ Forgejo is UP and healthy inside the VM!"
    if [ -z "${RESTORE_BACKUP}" ]; then
        echo "--> Creating default administrator account inside VM..."
        multipass exec "${VM_NAME}" -- sudo -u ubuntu bash -c "cd /home/ubuntu/git-server && make create-admin" >/dev/null 2>&1 || true
    fi
else
    echo "⚠️ Forgejo did not respond within 60s, but containers may still be initializing."
fi

echo "================================================================="
echo "  Deployment Complete! VM Info & Access"
echo "================================================================="
echo "  VM Name:       ${VM_NAME}"
echo "  VM IP Address: ${VM_IP}"
echo ""
echo "  Web UI:        http://${VM_IP}:3000"
echo "  Git over SSH:  ssh://git@${VM_IP}:222/<user>/<repo>.git"
if [ -z "${RESTORE_BACKUP}" ]; then
    echo ""
    echo "  Login Credentials (fresh VM):"
    echo "    Username:    ubuntu"
    echo "    Password:    admin-1234"
fi
echo ""
echo "  Useful Commands:"
echo "    Shell into VM:     multipass shell ${VM_NAME}"
echo "    Check services:    multipass exec ${VM_NAME} -- docker compose -f /home/ubuntu/git-server/docker-compose.yml ps"
echo "    Stop VM:           multipass stop ${VM_NAME}"
echo "    Delete VM:         multipass delete --purge ${VM_NAME}"
echo "================================================================="
