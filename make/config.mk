# -----------------------------------------------------------------------------
# Configuration and Environment Setup
# -----------------------------------------------------------------------------

.DEFAULT_GOAL := help

# Ensure .env file exists before running compose commands
ENV_FILE ?= .env
ifeq ($(wildcard $(ENV_FILE)),)
$(shell test -f .env.example && cp .env.example .env)
endif

COMPOSE := docker compose
BACKUP_DIR ?= $(or $(shell grep -E '^BACKUP_DIR=' $(ENV_FILE) 2>/dev/null | cut -d= -f2),$(HOME)/forgejo-backups)

# Multipass VM defaults
VM_NAME ?= git-server
VM_CPUS ?= 2
VM_MEM ?= 4G
VM_DISK ?= 20G

.PHONY: help

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
