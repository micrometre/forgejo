# -----------------------------------------------------------------------------
# KVM / Libvirt VM Lifecycle Targets (from ansible-kvm)
# -----------------------------------------------------------------------------

.PHONY: create_vm vm_status workspace clean_vm clean_all

create_vm: ## Create a new KVM VM (default: VM_NAME=git-runner, VM_IP=192.168.122.101)
	@echo "Creating KVM VM '$(VM_NAME)'..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_name=$(VM_NAME) vm_distro=$(VM_DISTRO) vm_vcpus=$(VM_CPUS) vm_ram=$(VM_RAM) vm_disk_size=$(VM_DISK) vm_static_ip=$(VM_IP)"

vm_status: ## Check status of a KVM VM (default: VM_NAME=git-runner)
	@echo "Checking KVM VM status..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_action=status vm_name=$(VM_NAME) vm_static_ip=$(VM_IP)"

workspace: ## Show KVM VMs overview, disk usage, and remote management URLs
	@echo "KVM Workspace Overview..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_action=overview"

clean_vm: ## Destroy and remove a specific KVM VM (default: VM_NAME=git-runner)
	@echo "Cleaning up KVM VM '$(VM_NAME)'..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags create-vm \
		-e "vm_cleanup=true vm_name=$(VM_NAME) vm_static_ip=$(VM_IP)"

clean_all: ## Remove cached VM cloud images and workspace directories (~/vm-workspace, ~/vm-images)
	@echo "Cleaning all cached VM workspace and cloud images..."
	rm -rf $(HOME)/vm-workspace
	rm -rf $(HOME)/vm-images
	@echo "✅ All VM workspace and cached cloud image data cleaned!"
