# -----------------------------------------------------------------------------
# Host Virtualization, VM Manager & Remote Access Setup (from ansible-kvm)
# -----------------------------------------------------------------------------

.PHONY: configure_virtualization configure_vm_manager kvm_remote_info kvm_port_forward

configure_virtualization: ## Configure KVM/libvirt virtualization & remote management (Cockpit + qemu+ssh)
	@echo "Configuring virtualization on $(HOST_NAME)..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags virtualization
	@echo "✅ $(HOST_NAME) configured with KVM virtualization and remote access!"

configure_vm_manager: ## Configure KVM VM manager workspace and cloud image cache
	@echo "Configuring VM manager on $(HOST_NAME)..."
	@ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook $(KVM_PLAYBOOK) --tags vm \
		-e "vm_action=none use_shared_images=true use_work_directory=true"
	@echo "✅ $(HOST_NAME) configured with VM manager!"

kvm_remote_info: ## Display connection commands to access & manage KVM VMs from another host
	@./scripts/kvm-remote-access.sh status

kvm_port_forward: ## Enable/disable host-to-VM port forwarding for LAN access (ACTION=enable|disable|status)
	@./scripts/kvm-remote-access.sh $(or $(ACTION),enable) --vm-ip $(VM_IP)
