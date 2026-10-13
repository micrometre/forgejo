#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Push Forgejo backup to Google Drive using rclone
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Load environment variables if .env exists
if [ -f "${ENV_FILE}" ]; then
    set -a
    # Load KEY=VALUE lines, ignoring comments
    eval "$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "${ENV_FILE}")"
    set +a
fi

# Configuration defaults
BACKUP_DIR="${BACKUP_DIR:-${HOME}/forgejo-backups}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive:Forgejo-Backups}"
CREATE_NEW_BACKUP=false
SYNC_ALL=false
SPECIFIC_FILE=""

# Parse options
for arg in "$@"; do
    case "$arg" in
        --new)
            CREATE_NEW_BACKUP=true
            ;;
        --all)
            SYNC_ALL=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [FILE]"
            echo ""
            echo "Options:"
            echo "  --new         Create a fresh backup before uploading"
            echo "  --all         Upload all backups in ${BACKUP_DIR} (skipping already uploaded)"
            echo "  [FILE]        Upload a specific backup file"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "Environment variables (or set in .env):"
            echo "  BACKUP_DIR    Directory containing backups (default: ~/forgejo-backups)"
            echo "  RCLONE_REMOTE rclone remote destination (default: gdrive:Forgejo-Backups)"
            exit 0
            ;;
        *)
            SPECIFIC_FILE="$arg"
            ;;
    esac
done

# Ensure rclone is installed
if ! command -v rclone &>/dev/null; then
    echo "Error: rclone is not installed or not in PATH." >&2
    exit 1
fi

# If --new requested, trigger make backup first
if [ "${CREATE_NEW_BACKUP}" = "true" ]; then
    echo "Creating a new backup..."
    make -C "${SCRIPT_DIR}" backup
fi

# Handle --all flag: copy all backups to remote
if [ "${SYNC_ALL}" = "true" ]; then
    echo "Syncing all backups from ${BACKUP_DIR} to ${RCLONE_REMOTE}..."
    rclone copy "${BACKUP_DIR}" "${RCLONE_REMOTE}" --include "forgejo-dump-*.zip" --progress
    echo "Sync completed successfully."
    exit 0
fi

# Identify the target backup file
if [ -n "${SPECIFIC_FILE}" ]; then
    TARGET_BACKUP="${SPECIFIC_FILE}"
else
    TARGET_BACKUP="$(ls -t "${BACKUP_DIR}"/forgejo-dump-*.zip 2>/dev/null | head -n1 || true)"
fi

if [ -z "${TARGET_BACKUP}" ] || [ ! -f "${TARGET_BACKUP}" ]; then
    echo "Error: No backup file found in ${BACKUP_DIR}." >&2
    echo "Run 'make backup' first, or pass '--new' to create one automatically." >&2
    exit 1
fi

FILENAME="$(basename "${TARGET_BACKUP}")"
echo "Found backup file: ${FILENAME} ($(du -h "${TARGET_BACKUP}" | cut -f1))"
echo "Uploading to ${RCLONE_REMOTE}/${FILENAME}..."

rclone copyto "${TARGET_BACKUP}" "${RCLONE_REMOTE}/${FILENAME}" --progress

echo ""
echo "Successfully pushed ${FILENAME} to ${RCLONE_REMOTE}!"
