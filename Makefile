# =============================================================================
# Forgejo Git Server - Main Makefile
# =============================================================================
# Modular targets are organized in the make/ directory:
#   make/config.mk     - Environment setup, default variables, help target
#   make/service.mk    - Service lifecycle (up, down, restart, logs, etc.)
#   make/admin.mk      - User and password administration
#   make/backup.mk     - Backups, verification, restore, and cleanup
#   make/multipass.mk  - Multipass VM testing and provisioning
# =============================================================================

include make/config.mk
include make/service.mk
include make/admin.mk
include make/backup.mk
include make/multipass.mk
include make/ansible.mk