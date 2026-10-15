#!/usr/bin/env bash
# =============================================================================
# backup_all_branches.sh
# Discovers and runs backup_branches.sh in all repository directories.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default search directory (parent of git-server if located in scripts/, or current directory)
if [ -d "/home/ubuntu/repos" ]; then
    DEFAULT_REPOS_DIR="/home/ubuntu/repos"
elif [ -d "${SCRIPT_DIR}/.." ] && [ -d "${SCRIPT_DIR}/../anpr-camera" ]; then
    DEFAULT_REPOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    DEFAULT_REPOS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

REPOS_DIR="${DEFAULT_REPOS_DIR}"
DRY_RUN=false
FAIL_FAST=false
QUIET=false
FILTER_REPO=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Finds and executes backup_branches.sh in all subdirectories of the repos directory.

Options:
  -d, --dir <path>     Directory containing repositories (default: ${DEFAULT_REPOS_DIR})
  -o, --only <name>    Only process repository matching <name>
  -n, --dry-run        List repositories that would be processed without running
  -f, --fail-fast      Exit immediately if any repository backup script fails
  -q, --quiet          Suppress per-repository details and show only the summary table
  -h, --help           Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --only anpr-hybrid-ocr
  $(basename "$0") --dry-run
  $(basename "$0") --dir /path/to/my/repos
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            REPOS_DIR="$2"
            shift 2
            ;;
        -o|--only)
            FILTER_REPO="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--fail-fast)
            FAIL_FAST=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
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

if [ ! -d "${REPOS_DIR}" ]; then
    echo "Error: Repositories directory '${REPOS_DIR}' not found." >&2
    exit 1
fi

# Discover all backup_branches.sh scripts
SCRIPTS=()
while IFS= read -r script_path; do
    if [ -n "${script_path}" ]; then
        repo_name="$(basename "$(dirname "${script_path}")")"
        if [ -n "${FILTER_REPO}" ] && [ "${repo_name}" != "${FILTER_REPO}" ]; then
            continue
        fi
        SCRIPTS+=("${script_path}")
    fi
done < <(find "${REPOS_DIR}" -maxdepth 2 -type f -name "backup_branches.sh" | sort)

TOTAL=${#SCRIPTS[@]}

if [ "${TOTAL}" -eq 0 ]; then
    echo "No 'backup_branches.sh' scripts found in '${REPOS_DIR}'."
    if [ -n "${FILTER_REPO}" ]; then
        echo "(Filter applied: --only '${FILTER_REPO}')"
    fi
    exit 0
fi

echo "================================================================="
echo "  Run All Repository Branch Backups"
echo "================================================================="
echo "Directory:     ${REPOS_DIR}"
echo "Scripts Found: ${TOTAL}"
if [ -n "${FILTER_REPO}" ]; then
    echo "Filter:        --only '${FILTER_REPO}'"
fi
echo "Time:          $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================="
echo ""

if [ "${DRY_RUN}" = "true" ]; then
    echo "Dry run enabled. Repositories that would be backed up:"
    idx=1
    for s in "${SCRIPTS[@]}"; do
        rname="$(basename "$(dirname "${s}")")"
        echo "  [${idx}/${TOTAL}] ${rname} -> ${s}"
        idx=$((idx + 1))
    done
    echo ""
    echo "Done (dry-run)."
    exit 0
fi

START_TOTAL=$(date +%s)
SUCCESSFUL=0
FAILED=0

declare -a REPORT_REPOS=()
declare -a REPORT_STATUS=()
declare -a REPORT_DURATIONS=()

idx=1
for script in "${SCRIPTS[@]}"; do
    repo_dir="$(dirname "${script}")"
    repo_name="$(basename "${repo_dir}")"

    echo "-----------------------------------------------------------------"
    echo "[${idx}/${TOTAL}] Processing: ${repo_name}"
    echo "Directory: ${repo_dir}"
    echo "-----------------------------------------------------------------"

    start_repo=$(date +%s)
    set +e
    if [ "${QUIET}" = "true" ]; then
        (cd "${repo_dir}" && bash "./backup_branches.sh") >/dev/null 2>&1
        exit_code=$?
    else
        (cd "${repo_dir}" && bash "./backup_branches.sh")
        exit_code=$?
    fi
    set -e
    end_repo=$(date +%s)
    duration=$((end_repo - start_repo))

    REPORT_REPOS+=("${repo_name}")
    REPORT_DURATIONS+=("${duration}s")

    if [ ${exit_code} -eq 0 ]; then
        echo "✓ ${repo_name}: SUCCESS (${duration}s)"
        REPORT_STATUS+=("SUCCESS")
        SUCCESSFUL=$((SUCCESSFUL + 1))
    else
        echo "✗ ${repo_name}: FAILED (exit code: ${exit_code}, ${duration}s)" >&2
        REPORT_STATUS+=("FAILED")
        FAILED=$((FAILED + 1))
        if [ "${FAIL_FAST}" = "true" ]; then
            echo "Stopping early due to --fail-fast flag." >&2
            break
        fi
    fi
    echo ""
    idx=$((idx + 1))
done

END_TOTAL=$(date +%s)
TOTAL_DURATION=$((END_TOTAL - START_TOTAL))

echo "================================================================="
echo "  Backup All Branches - Summary Report"
echo "================================================================="
echo "Total Repositories: ${TOTAL}"
echo "Successful:         ${SUCCESSFUL}"
echo "Failed:             ${FAILED}"
echo "Total Duration:     ${TOTAL_DURATION}s"
echo "-----------------------------------------------------------------"
printf "  %-28s %-12s %-10s\n" "Repository" "Status" "Duration"
printf "  %-28s %-12s %-10s\n" "----------------------------" "------------" "----------"

for i in "${!REPORT_REPOS[@]}"; do
    r="${REPORT_REPOS[$i]}"
    s="${REPORT_STATUS[$i]}"
    d="${REPORT_DURATIONS[$i]}"
    printf "  %-28s %-12s %-10s\n" "${r}" "${s}" "${d}"
done
echo "================================================================="

if [ "${FAILED}" -gt 0 ]; then
    echo "Warning: ${FAILED} repository backup(s) failed." >&2
    exit 1
else
    echo "All ${SUCCESSFUL} repositories successfully synchronized!"
    exit 0
fi
