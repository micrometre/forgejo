# -----------------------------------------------------------------------------
# Ansible Infrastructure as Code Targets (Host Git Server + KVM Runner)
# -----------------------------------------------------------------------------

.PHONY: ansible-ping ansible-deploy ansible-server ansible-app ansible-backup ansible-restore \
        ansible-kvm-runner ansible-runner

ansible-ping: ## Test Ansible connectivity across all inventory hosts (host git-server + KVM git-runner)
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible all -i $(INVENTORY) -m ping

ansible-deploy: ## Run full Ansible site playbook (host git-server + KVM git-runner)
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/site.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-server: ## Deploy/update Forgejo Git Server on the host ([git_servers])
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy-git-server.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-app: ansible-server ## Alias for ansible-server

ansible-backup: ## Create Forgejo backup on [git_servers] and save to ~/forgejo-backups
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/backup.yml \
		-e "host_backup_dir=$(BACKUP_DIR)" $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-restore: ## Restore backup from ~/forgejo-backups to [git_servers] (usage: make ansible-restore [FILE=...])
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/restore.yml \
		$(if $(FILE),-e "backup_src=$(FILE)",) $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-kvm-runner: ## Create KVM Runner VM ('git-runner') and register it with Host Forgejo Server
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/provision-runner-kvm.yml \
		-e "runner_vm_name=$(RUNNER_VM_NAME) runner_vm_distro=$(VM_DISTRO) runner_vm_vcpus=$(RUNNER_VM_CPUS) runner_vm_ram=$(VM_RAM) runner_vm_disk_size=$(RUNNER_VM_DISK) runner_vm_ip=$(RUNNER_VM_IP)" \
		$(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-runner: ## Provision and register Forgejo Actions Runner on [git_runners] (use EXTRA_VARS="forgejo_runner_force_register=true" to re-register)
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy-runner.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)
