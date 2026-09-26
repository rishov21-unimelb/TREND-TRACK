# Instagram Trend Tracker — common tasks.
# Every target works from the repository root.

SHELL := /bin/sh
SERVER := server
CLIENT := client

.DEFAULT_GOAL := help
.PHONY: help install dev dev-server dev-client seed reseed ingest test test-watch \
        typecheck build build-server build-client preview up down restart logs ps \
        rebuild reset clean

## ---------------------------------------------------------------- meta ----

help: ## Show this help
	@echo "Instagram Trend Tracker"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## ------------------------------------------------------------- local dev ---

install: ## Install server and client dependencies
	cd $(SERVER) && npm install
	cd $(CLIENT) && npm install

dev: ## Run the API and the Vite dev server together
	@echo "Starting API on :4000 and client on :5173 — Ctrl-C stops both"
	@$(MAKE) -j2 dev-server dev-client

dev-server: ## Run only the API (tsx watch, port 4000)
	cd $(SERVER) && npm run dev

dev-client: ## Run only the client (Vite, port 5173, proxies /api)
	cd $(CLIENT) && npm run dev

seed: ## Backfill trend history if the database is empty
	cd $(SERVER) && npm run seed

reseed: ## Wipe and regenerate the dataset from the configured seed
	cd $(SERVER) && npm run seed -- --force

ingest: ## Run one ingestion cycle (live source first, generator as fallback)
	cd $(SERVER) && npm run ingest

## ---------------------------------------------------------------- checks ---

test: ## Run the backend test suite
	cd $(SERVER) && npm test

test-watch: ## Run the backend tests in watch mode
	cd $(SERVER) && npm run test:watch

typecheck: ## Type-check the backend
	cd $(SERVER) && npm run typecheck

## ----------------------------------------------------------------- build ---

build: build-server build-client ## Build both packages

build-server: ## Compile the API to server/dist
	cd $(SERVER) && npm run build

build-client: ## Bundle the client to client/dist
	cd $(CLIENT) && npm run build

preview: ## Serve the built client on :4173
	cd $(CLIENT) && npm run preview

## ---------------------------------------------------------------- docker ---

up: ## Start the stack (client on :8080, API on :4000)
	docker compose up -d --build
	@echo "Client  http://localhost:8080"
	@echo "API     http://localhost:4000/api"

down: ## Stop the stack
	docker compose down

restart: down up ## Restart the stack

rebuild: ## Rebuild images without cache and start
	docker compose build --no-cache
	docker compose up -d

logs: ## Tail container logs
	docker compose logs -f --tail=100

ps: ## Show container status
	docker compose ps

## --------------------------------------------------------------- cleanup ---

reset: ## Drop the local SQLite database and regenerate it
	rm -f $(SERVER)/data/trends.db $(SERVER)/data/trends.db-wal $(SERVER)/data/trends.db-shm
	cd $(SERVER) && npm run seed -- --force

clean: ## Remove build output, dependencies and the docker volume
	rm -rf $(SERVER)/dist $(SERVER)/node_modules $(CLIENT)/dist $(CLIENT)/node_modules
	-docker compose down -v
