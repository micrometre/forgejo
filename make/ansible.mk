# -----------------------------------------------------------------------------
# Ansible Infrastructure as Code Targets
# -----------------------------------------------------------------------------

ANSIBLE_DIR := ansible
ANSIBLE_CFG := $(ANSIBLE_DIR)/ansible.cfg
INVENTORY ?= $(ANSIBLE_DIR)/inventory/hosts.ini
EXTRA_VARS ?=

.PHONY: ansible-ping ansible-deploy ansible-app ansible-vm

ansible-ping: ## Test Ansible SSH connectivity across all inventory hosts
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible git_servers -i $(INVENTORY) -m ping

ansible-deploy: ## Run full Ansible site playbook (baseline + docker + git-server)
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/site.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-app: ## Deploy/update Git Server application stack only (skips OS packages)
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy-git-server.yml $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)

ansible-vm: ## Launch Multipass VM and provision completely with Ansible
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(ANSIBLE_DIR)/playbooks/provision-multipass.yml \
		-e "vm_name=$(VM_NAME) vm_cpus=$(VM_CPUS) vm_memory=$(VM_MEM) vm_disk=$(VM_DISK)" $(if $(EXTRA_VARS),-e "$(EXTRA_VARS)",)
