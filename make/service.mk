# -----------------------------------------------------------------------------
# Service Lifecycle and Container Management
# -----------------------------------------------------------------------------

.PHONY: init up down restart ps status logs logs-server logs-db pull shell

init: ## Initialize environment file and required data directories
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env from .env.example"; \
	else \
		echo ".env already exists"; \
	fi
	@mkdir -p data/forgejo data/postgres
	@echo "Created data directories: ./data/forgejo, ./data/postgres"

up: init ## Start Forgejo and PostgreSQL services in background
	$(COMPOSE) up -d
	@echo ""
	@echo "Forgejo is starting up!"
	@echo "Web UI: http://localhost:$$(grep -E '^FORGEJO_HTTP_PORT=' .env 2>/dev/null | cut -d= -f2 || echo 3000)"
	@echo "SSH:    ssh -p $$(grep -E '^FORGEJO_SSH_PORT=' .env 2>/dev/null | cut -d= -f2 || echo 222) git@localhost"

down: ## Stop all services and network
	$(COMPOSE) down

restart: ## Restart all services
	$(COMPOSE) restart

ps: ## Display container status
	$(COMPOSE) ps

status: ps ## Alias for 'ps'

logs: ## Tail logs for all services
	$(COMPOSE) logs -f

logs-server: ## Tail logs for Forgejo server
	$(COMPOSE) logs -f server

logs-db: ## Tail logs for PostgreSQL database
	$(COMPOSE) logs -f db

pull: ## Pull updated Docker images
	$(COMPOSE) pull

shell: ## Open a shell inside the Forgejo server container
	$(COMPOSE) exec server /bin/sh
