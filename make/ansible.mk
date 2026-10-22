# -----------------------------------------------------------------------------
# Ansible Infrastructure as Code Targets
# -----------------------------------------------------------------------------

ANSIBLE_DIR := ansible
ANSIBLE_CFG := $(ANSIBLE_DIR)/ansible.cfg
INVENTORY ?= $(ANSIBLE_DIR)/inventory/hosts.ini
EXTRA_VARS ?=

.PHONY: ansible-ping ansible-deploy ansible-app ansible-vm ansible-restore ansible-runner ansible-runner-vm

ansible-ping: ## Test Ansible SSH connectivity across all inventory hosts
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible all -i $(INVENTORY) -m ping

ansible-deploy: ## Run full Ansible site playbook (baseline + docker + git-server + runners)
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/site.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-app: ## Deploy/update Git Server application stack only (skips OS packages)
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy-git-server.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-restore: ## Restore backup from host to inventory servers (usage: make ansible-restore [FILE=...])
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/restore.yml \
		$(if $(FILE),-e "backup_src=$(FILE)",) $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-vm: ## Launch Multipass VM and provision completely with Ansible
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(ANSIBLE_DIR)/playbooks/provision-multipass.yml \
		-e "vm_name=$(VM_NAME) vm_cpus=$(VM_CPUS) vm_memory=$(VM_MEM) vm_disk=$(VM_DISK)" $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-runner: ## Provision and register Forgejo Actions Runner on inventory [git_runners] hosts
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy-runner.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-runner-vm: ## Launch Multipass Runner VM ('git-runner') and register it with Forgejo via Ansible
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/provision-runner-multipass.yml \
		-e "runner_vm_name=$(RUNNER_VM_NAME) runner_vm_cpus=$(VM_CPUS) runner_vm_memory=$(VM_MEM) runner_vm_disk=$(VM_DISK)" $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)
