# -----------------------------------------------------------------------------
# Backup, Verification, Restore, and Branch Sync (via Ansible & Scripts)
# -----------------------------------------------------------------------------

.PHONY: backup backup-gdrive check-backup verify-backup restore backup-branches backup-all-branches

backup: ansible-backup ## Create Forgejo backup on git-server VM via Ansible and save to ~/forgejo-backups

restore: ansible-restore ## Restore Forgejo instance on git-server VM from backup (usage: make restore [FILE=...])

backup-gdrive: ## Push latest backup to Google Drive using rclone (use ARGS=--new to create fresh backup first)
	@./scripts/backup-to-gdrive.sh $(ARGS)

backup-branches: ## Sync all branch backups across repositories in ~/repos (usage: make backup-branches [ARGS="--dry-run|--only <repo>|--quiet"])
	@./scripts/backup-all-branches.sh $(ARGS)

backup-all-branches: backup-branches ## Alias for backup-branches

check-backup: ## Verify backup archive integrity and completeness (usage: make check-backup [FILE=path/to/dump.zip])
	@./scripts/verify-backup.sh $(FILE)

verify-backup: check-backup ## Alias for check-backup
