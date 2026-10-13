.DEFAULT_GOAL := help

# Ensure .env file exists before running compose commands
ENV_FILE ?= .env
ifeq ($(wildcard $(ENV_FILE)),)
$(shell test -f .env.example && cp .env.example .env)
endif

COMPOSE := docker compose
BACKUP_DIR ?= $(or $(shell grep -E '^BACKUP_DIR=' $(ENV_FILE) 2>/dev/null | cut -d= -f2),$(HOME)/forgejo-backups)

.PHONY: help init up down restart ps status logs logs-server logs-db pull shell create-admin reset-password backup backup-gdrive restore clean

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

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

create-admin: ## Create an initial administrator account (defaults: username=ubuntu)
	@echo "Creating Forgejo administrator user..."
	@$(COMPOSE) exec --user git server forgejo admin user create \
		--admin \
		--username $(or $(ADMIN_USER),ubuntu) \
		--password $(or $(ADMIN_PASS),admin-1234) \
		--email $(or $(ADMIN_EMAIL),admin@example.local) \
		--must-change-password=false
	@echo "Admin user '$(or $(ADMIN_USER),ubuntu)' created successfully!"

reset-password: ## Reset a user's password (usage: make reset-password USER=ubuntu PASS=admin-1234)
	@$(COMPOSE) exec --user git server forgejo admin user change-password \
		--username $(or $(USER),ubuntu) \
		--password $(or $(PASS),admin-1234) \
		--must-change-password=false
	@echo "Password for '$(or $(USER),ubuntu)' updated successfully!"

backup: ## Run Forgejo backup dump and save archive in BACKUP_DIR (default: ~/forgejo-backups)
	@mkdir -p "$(BACKUP_DIR)"
	@echo "Creating Forgejo backup..."
	@$(COMPOSE) exec --user git server forgejo dump -c /data/gitea/conf/app.ini -f /tmp/forgejo-dump.zip
	@DUMP_FILE="$(BACKUP_DIR)/forgejo-dump-$$(date +%Y%m%d_%H%M%S).zip"; \
	$(COMPOSE) cp server:/tmp/forgejo-dump.zip "$$DUMP_FILE"; \
	$(COMPOSE) exec server rm -f /tmp/forgejo-dump.zip; \
	TMP_DIR=$$(mktemp -d); \
	DB_USER=$$(grep -E '^POSTGRES_USER=' .env 2>/dev/null | cut -d= -f2 || echo forgejo); \
	DB_NAME=$$(grep -E '^POSTGRES_DB=' .env 2>/dev/null | cut -d= -f2 || echo forgejo); \
	$(COMPOSE) exec -T db pg_dump -U "$$DB_USER" "$$DB_NAME" > "$$TMP_DIR/forgejo-postgres.sql" 2>/dev/null && \
	zip -j -u -q "$$DUMP_FILE" "$$TMP_DIR/forgejo-postgres.sql" 2>/dev/null || true; \
	rm -rf "$$TMP_DIR"; \
	echo "Backup completed. Saved in $$DUMP_FILE"

backup-gdrive: ## Push latest backup to Google Drive using rclone (use ARGS=--new to create fresh backup first)
	@./scripts/backup-to-gdrive.sh $(ARGS)

restore: init ## Restore instance from a backup file (usage: make restore [FILE=path/to/dump.zip])
	@RESTORE_FILE="$(FILE)"; \
	if [ -z "$$RESTORE_FILE" ]; then \
		RESTORE_FILE=$$(ls -t "$(BACKUP_DIR)"/forgejo-dump-*.zip 2>/dev/null | head -n1); \
	fi; \
	if [ -z "$$RESTORE_FILE" ]; then \
		RESTORE_FILE=$$(ls -t backups/forgejo-dump-*.zip 2>/dev/null | head -n1); \
	fi; \
	if [ -z "$$RESTORE_FILE" ] || [ ! -f "$$RESTORE_FILE" ]; then \
		echo "Error: No backup archive found in $(BACKUP_DIR) or ./backups. Specify one with FILE=/path/to/file.zip"; \
		exit 1; \
	fi; \
	echo "Found backup file: $$RESTORE_FILE"; \
	read -p "WARNING: This will overwrite existing database and repository data. Proceed? [y/N] " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "Restore aborted."; \
		exit 0; \
	fi; \
	echo "Starting restore from $$RESTORE_FILE..."; \
	DB_USER=$$(grep -E '^POSTGRES_USER=' .env 2>/dev/null | cut -d= -f2 || echo forgejo); \
	DB_NAME=$$(grep -E '^POSTGRES_DB=' .env 2>/dev/null | cut -d= -f2 || echo forgejo); \
	$(COMPOSE) up -d --wait db >/dev/null 2>&1 || $(COMPOSE) up -d db >/dev/null 2>&1; \
	until $(COMPOSE) exec -T db pg_isready -U "$$DB_USER" -d "$$DB_NAME" >/dev/null 2>&1; do \
		sleep 1; \
	done; \
	$(COMPOSE) stop server >/dev/null 2>&1 || true; \
	TMP_DIR=$$(mktemp -d); \
	unzip -q "$$RESTORE_FILE" -d "$$TMP_DIR"; \
	echo "Restoring database..."; \
	$(COMPOSE) exec -T db psql -U "$$DB_USER" -d "$$DB_NAME" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO \"$$DB_USER\";" >/dev/null; \
	if [ -f "$$TMP_DIR/forgejo-postgres.sql" ]; then \
		$(COMPOSE) exec -T db psql -U "$$DB_USER" -d "$$DB_NAME" < "$$TMP_DIR/forgejo-postgres.sql" >/dev/null; \
	elif [ -f "$$TMP_DIR/forgejo-db.sql" ]; then \
		$(COMPOSE) exec -T db psql -U "$$DB_USER" -d "$$DB_NAME" < "$$TMP_DIR/forgejo-db.sql" >/dev/null 2>&1 || true; \
	fi; \
	echo "Restoring repositories and data files..."; \
	docker run --rm -v "$$TMP_DIR:/src" -v "$$(pwd)/data/forgejo:/dst" alpine sh -c "\
		rm -rf /dst/git /dst/gitea; \
		mkdir -p /dst/git/repositories /dst/git/.ssh /dst/gitea/conf /dst/gitea/log; \
		if [ -d /src/repos ]; then cp -a /src/repos/. /dst/git/repositories/; fi; \
		if [ -d /src/data ]; then cp -a /src/data/. /dst/gitea/; fi; \
		chown -R 1000:1000 /dst; \
		chmod 700 /dst/git/.ssh 2>/dev/null || true; \
	"; \
	rm -rf "$$TMP_DIR"; \
	echo "Starting Forgejo server..."; \
	$(COMPOSE) up -d server; \
	sleep 4; \
	docker run --rm -v "$$(pwd)/data/forgejo:/data" alpine chown -R 1000:1000 /data/gitea/log /data/git/.ssh 2>/dev/null || true; \
	$(COMPOSE) exec --user git server forgejo doctor check -c /data/gitea/conf/app.ini --run authorized-keys --fix >/dev/null 2>&1 || true; \
	echo "Restore completed successfully from $$RESTORE_FILE!"

clean: ## Stop services and delete persistent data (data/)
	@echo "WARNING: This will permanently remove all persistent data in ./data!"
	@read -p "Are you sure you want to proceed? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		$(COMPOSE) down -v; \
		if [ -d data ]; then \
			docker run --rm -v "$$(pwd):/work" alpine rm -rf /work/data 2>/dev/null || rm -rf data 2>/dev/null || sudo rm -rf data 2>/dev/null || true; \
		fi; \
		echo "Cleaned up containers, networks, and ./data."; \
	else \
		echo "Aborted."; \
	fi
