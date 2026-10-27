#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Restore Forgejo & PostgreSQL inside Target Server (Invoked by Ansible)
# -----------------------------------------------------------------------------

RESTORE_FILE="${1:-}"
if [ -z "${RESTORE_FILE}" ] || [ ! -f "${RESTORE_FILE}" ]; then
    echo "Error: Valid backup archive path required. Usage: $0 /path/to/backup.zip" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

DB_USER="$(grep -E '^POSTGRES_USER=' .env 2>/dev/null | cut -d= -f2 || echo forgejo)"
DB_NAME="$(grep -E '^POSTGRES_DB=' .env 2>/dev/null | cut -d= -f2 || echo forgejo)"

echo "Starting restore from ${RESTORE_FILE}..."
docker compose up -d --wait db >/dev/null 2>&1 || docker compose up -d db >/dev/null 2>&1
until docker compose exec -T db pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
    sleep 1
done

docker compose stop server >/dev/null 2>&1 || true

TMP_DIR="$(mktemp -d)"
unzip -q "${RESTORE_FILE}" -d "${TMP_DIR}"

echo "Restoring PostgreSQL database..."
docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" \
    -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO \"${DB_USER}\";" >/dev/null

if [ -f "${TMP_DIR}/forgejo-postgres.sql" ]; then
    docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" < "${TMP_DIR}/forgejo-postgres.sql" >/dev/null
elif [ -f "${TMP_DIR}/forgejo-db.sql" ]; then
    docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" < "${TMP_DIR}/forgejo-db.sql" >/dev/null 2>&1 || true
fi

echo "Restoring repositories and data files..."
docker run --rm -v "${TMP_DIR}:/src" -v "${SCRIPT_DIR}/data/forgejo:/dst" alpine sh -c "
    rm -rf /dst/git /dst/gitea
    mkdir -p /dst/git/repositories /dst/git/.ssh /dst/gitea/conf /dst/gitea/log
    if [ -d /src/repos ]; then cp -a /src/repos/. /dst/git/repositories/; fi
    if [ -d /src/data ]; then cp -a /src/data/. /dst/gitea/; fi
    chown -R 1000:1000 /dst
    chmod 700 /dst/git/.ssh 2>/dev/null || true
"

rm -rf "${TMP_DIR}"

echo "Starting Forgejo server..."
docker compose up -d server
sleep 4
docker run --rm -v "${SCRIPT_DIR}/data/forgejo:/data" alpine chown -R 1000:1000 /data/gitea/log /data/git/.ssh 2>/dev/null || true
docker compose exec --user git server forgejo doctor check -c /data/gitea/conf/app.ini --run authorized-keys --fix >/dev/null 2>&1 || true
echo "Restore completed successfully from ${RESTORE_FILE}!"
