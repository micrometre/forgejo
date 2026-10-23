#!/usr/bin/env bash
# backup_branches.sh
# Synchronizes all branches from origin into local tracking branches and pushes them to the backup remote.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REMOTE_ORIGIN="${REMOTE_ORIGIN:-origin}"
REMOTE_BACKUP="${REMOTE_BACKUP:-backup}"
BACKUP_URL="${BACKUP_URL:-git@git.vm:ubuntu/git-server}"

echo "================================================="
echo " ANPR Git Repository - Backup All Branches"
echo "================================================="
echo "Source remote: $REMOTE_ORIGIN"
echo "Target remote: $REMOTE_BACKUP ($BACKUP_URL)"
echo ""

# 1. Ensure backup remote is configured
if git remote get-url "$REMOTE_BACKUP" >/dev/null 2>&1; then
    current_url="$(git remote get-url "$REMOTE_BACKUP")"
    if [[ "$current_url" != "$BACKUP_URL" ]]; then
        echo "→ Updating remote '$REMOTE_BACKUP' URL from '$current_url' to '$BACKUP_URL'"
        git remote set-url "$REMOTE_BACKUP" "$BACKUP_URL"
    else
        echo "✓ Remote '$REMOTE_BACKUP' is configured: $current_url"
    fi
else
    echo "→ Adding remote '$REMOTE_BACKUP' -> $BACKUP_URL"
    git remote add "$REMOTE_BACKUP" "$BACKUP_URL"
fi

# 2. Fetch latest changes from source remote
echo ""
echo "→ Fetching latest changes from '$REMOTE_ORIGIN'..."
git fetch "$REMOTE_ORIGIN" --prune --tags

# 3. Synchronize local branches with origin
echo ""
echo "→ Synchronizing local branches with '$REMOTE_ORIGIN'..."
current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

for full_ref in $(git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE_ORIGIN"); do
    # Skip symbolic HEAD ref (e.g. refs/remotes/origin/HEAD)
    if [[ "$full_ref" == "refs/remotes/$REMOTE_ORIGIN/HEAD" ]]; then
        continue
    fi

    branch_name="${full_ref#refs/remotes/$REMOTE_ORIGIN/}"
    short_ref="${full_ref#refs/remotes/}"

    # Check if local branch already exists
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        if [[ "$branch_name" == "$current_branch" ]]; then
            # Current branch: fast-forward merge if possible
            echo "  [updating current] $branch_name"
            git merge --ff-only "$short_ref" 2>/dev/null || echo "  [warning] could not fast-forward checked out branch '$branch_name'"
        else
            # Non-checked-out branch: update ref to origin commit directly
            target_commit="$(git rev-parse "$full_ref")"
            local_commit="$(git rev-parse "refs/heads/$branch_name")"
            if [[ "$local_commit" != "$target_commit" ]]; then
                echo "  [updated] $branch_name -> $short_ref"
                git branch -f "$branch_name" "$short_ref" >/dev/null
            else
                echo "  [up-to-date] $branch_name"
            fi
        fi
    else
        echo "  [created] $branch_name -> $short_ref"
        git branch --track "$branch_name" "$short_ref" >/dev/null
    fi
done

# 4. Push all branches to the backup remote
echo ""
echo "→ Pushing all branches to '$REMOTE_BACKUP'..."
git push "$REMOTE_BACKUP" --all

# 5. Push any tags
echo ""
echo "→ Pushing tags to '$REMOTE_BACKUP'..."
git push "$REMOTE_BACKUP" --tags 2>/dev/null || true

# 6. Fetch backup to refresh tracking refs
echo ""
echo "→ Updating local view of '$REMOTE_BACKUP'..."
git fetch "$REMOTE_BACKUP" --prune 2>/dev/null || true

echo ""
echo "================================================="
echo "✓ All branches successfully synchronized to $REMOTE_BACKUP!"
echo "================================================="
echo ""
echo "Current branch inventory (git branch -a):"
git --no-pager branch -a
