# -----------------------------------------------------------------------------
# Multipass VM Testing & Provisioning
# -----------------------------------------------------------------------------

.PHONY: vm-status provision-vm provision_vm vm-restore sshkey-multipass vm-shell vm-clean

vm-status: ## List all Multipass VMs and their status
	@multipass list

provision-vm: ## Provision and deploy Git Server into a Multipass VM
	@./scripts/provision-vm.sh --name $(VM_NAME) --cpus $(VM_CPUS) --memory $(VM_MEM) --disk $(VM_DISK)

provision_vm: provision-vm ## Alias for provision-vm

vm-restore: ## Provision VM and test-restore the latest backup (or FILE=...)
	@./scripts/provision-vm.sh --name $(VM_NAME) --cpus $(VM_CPUS) --memory $(VM_MEM) --disk $(VM_DISK) --restore $(FILE)

sshkey-multipass: ## Copy host SSH public keys into the Multipass VM
	@mkdir -p ~/.ssh
	@cat ~/.ssh/*.pub 2>/dev/null | multipass exec $(VM_NAME) -- tee -a .ssh/authorized_keys >/dev/null || true
	@echo "Injected SSH public keys into $(VM_NAME)"

vm-shell: ## Open an interactive shell inside the Multipass VM
	@multipass shell $(VM_NAME)

vm-clean: ## Stop and delete the Multipass test VM
	@multipass delete --purge $(VM_NAME)
