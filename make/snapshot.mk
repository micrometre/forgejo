# -----------------------------------------------------------------------------
# KVM VM Snapshot Management Targets (from ansible-kvm)
# -----------------------------------------------------------------------------

.PHONY: snapshot snapshot_create snapshot_list snapshot_revert snapshot_delete snapshot_clone create_vm_from_snapshot

snapshot: snapshot_create ## Create a snapshot of a KVM VM (alias for snapshot_create)

snapshot_create: ## Create a snapshot of VM_NAME (optional: SNAPSHOT_NAME=..., SNAPSHOT_DESC=...)
	@echo "Creating KVM VM snapshot..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_action=snapshot_create vm_name=$(VM_NAME)" \
		$(if $(SNAPSHOT_NAME),-e "snapshot_name=$(SNAPSHOT_NAME)",) \
		$(if $(SNAPSHOT_DESC),-e "snapshot_description='$(SNAPSHOT_DESC)'",)

snapshot_list: ## List all snapshots for VM_NAME (default: VM_NAME=git-server)
	@echo "Listing KVM VM snapshots..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_action=snapshot_list vm_name=$(VM_NAME)"

snapshot_revert: ## Revert VM_NAME to a snapshot (requires SNAPSHOT_NAME=...)
	@echo "Reverting KVM VM to snapshot..."
	@if [ -z "$(SNAPSHOT_NAME)" ]; then echo "ERROR: SNAPSHOT_NAME is required. Usage: make snapshot_revert SNAPSHOT_NAME=my_snap [VM_NAME=git-server]"; exit 1; fi
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_action=snapshot_revert vm_name=$(VM_NAME) snapshot_name=$(SNAPSHOT_NAME)"

snapshot_delete: ## Delete a snapshot from VM_NAME (requires SNAPSHOT_NAME=...)
	@echo "Deleting KVM VM snapshot..."
	@if [ -z "$(SNAPSHOT_NAME)" ]; then echo "ERROR: SNAPSHOT_NAME is required. Usage: make snapshot_delete SNAPSHOT_NAME=my_snap [VM_NAME=git-server]"; exit 1; fi
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_action=snapshot_delete vm_name=$(VM_NAME) snapshot_name=$(SNAPSHOT_NAME)"

create_vm_from_snapshot: snapshot_clone

snapshot_clone: ## Clone a new KVM VM from a snapshot (requires SNAPSHOT_NAME=..., NEW_VM_NAME=...)
	@echo "Creating new KVM VM from snapshot..."
	@if [ -z "$(SNAPSHOT_NAME)" ] || [ -z "$(NEW_VM_NAME)" ]; then echo "ERROR: SNAPSHOT_NAME and NEW_VM_NAME are required. Usage: make snapshot_clone SNAPSHOT_NAME=my_snap NEW_VM_NAME=cloned_vm [VM_NAME=git-server]"; exit 1; fi
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_action=snapshot_clone vm_name=$(VM_NAME) snapshot_name=$(SNAPSHOT_NAME) new_vm_name=$(NEW_VM_NAME)"
