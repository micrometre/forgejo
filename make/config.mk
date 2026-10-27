# -----------------------------------------------------------------------------
# Configuration and Defaults (Ansible + KVM / Libvirt)
# -----------------------------------------------------------------------------

.DEFAULT_GOAL := help

BACKUP_DIR ?= $(HOME)/forgejo-backups

# Ansible paths
ANSIBLE_DIR := ansible
ANSIBLE_CFG := $(ANSIBLE_DIR)/ansible.cfg
INVENTORY ?= $(ANSIBLE_DIR)/inventory/hosts.ini
KVM_PLAYBOOK := $(ANSIBLE_DIR)/playbooks/configure-kvm.yml
EXTRA_VARS ?=

# KVM / Libvirt VM defaults (matching ansible-kvm)
HOST_NAME ?= $(shell hostname)
VM_NAME ?= git-server
RUNNER_VM_NAME ?= git-runner
VM_DISTRO ?= noble
VM_CPUS ?= 2
RUNNER_VM_CPUS ?= 4
VM_RAM ?= 4096
VM_DISK ?= 20G
RUNNER_VM_DISK ?= 60G
VM_IP ?= 192.168.122.100
RUNNER_VM_IP ?= 192.168.122.101

.PHONY: help

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -h -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'
