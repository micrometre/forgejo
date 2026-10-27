# =============================================================================
# Forgejo Git Server & KVM Infrastructure (Ansible IaC) - Main Makefile
# =============================================================================
# Modular targets are organized in the make/ directory:
#   make/config.mk     - Default variables and help target
#   make/setup.mk      - Host KVM/libvirt & remote management setup
#   make/vm.mk         - KVM VM creation, status, workspace, and cleanup
#   make/snapshot.mk   - KVM VM snapshot management (create, list, revert, clone)
#   make/ansible.mk    - Ansible Git Server & Runner provisioning targets
#   make/backup.mk     - Ansible-driven backups, verification, restore, and sync
# =============================================================================

include make/config.mk
include make/setup.mk
include make/vm.mk
include make/snapshot.mk
include make/ansible.mk
include make/backup.mk
