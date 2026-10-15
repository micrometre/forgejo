# -----------------------------------------------------------------------------
# User and Administrator Management
# -----------------------------------------------------------------------------

.PHONY: create-admin reset-password

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
