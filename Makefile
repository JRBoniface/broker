# Makefile for building broker container image
# Copyright 2025 Kyndryl, All Rights Reserved

# Variables
IMAGE_NAME ?= broker
IMAGE_TAG ?= latest
IMAGE_REGISTRY ?= ghrc.io
IMAGE_REPO ?= $(IMAGE_REGISTRY)/$(IMAGE_NAME)
FULL_IMAGE ?= $(IMAGE_REPO):$(IMAGE_TAG)

DOCKERFILE ?= Dockerfile
DOCKER_BUILD_ARGS ?=

# Docker/Podman detection
CONTAINER_CLI ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)

# Network (shared with trader)
NETWORK_NAME ?= trader-network

# OpenTelemetry configuration
OTEL_CONTAINER ?= otel-collector

.PHONY: help
help: ## Display this help message
	@echo "Broker Image Build Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'


.PHONY: build
build: ## Build the container image
	@echo "Building image: $(FULL_IMAGE)"
	mvn clean package
	$(CONTAINER_CLI) build $(DOCKER_BUILD_ARGS) -t $(FULL_IMAGE) -f $(DOCKERFILE) .
	@echo "Successfully built: $(FULL_IMAGE)"

.PHONY: build-no-cache
build-no-cache: ## Build the container image without cache
	@echo "Building image without cache: $(FULL_IMAGE)"
	$(CONTAINER_CLI) build --no-cache $(DOCKER_BUILD_ARGS) -t $(FULL_IMAGE) -f $(DOCKERFILE) .
	@echo "Successfully built: $(FULL_IMAGE)"

.PHONY: tag
tag: ## Tag the image with additional tags (usage: make tag TAG=v1.0.0)
	@if [ -z "$(TAG)" ]; then \
		echo "Error: TAG variable is required. Usage: make tag TAG=v1.0.0"; \
		exit 1; \
	fi
	@echo "Tagging $(FULL_IMAGE) as $(IMAGE_REPO):$(TAG)"
	$(CONTAINER_CLI) tag $(FULL_IMAGE) $(IMAGE_REPO):$(TAG)

.PHONY: push
push: ## Push the image to registry
	@echo "Pushing image: $(FULL_IMAGE)"
	$(CONTAINER_CLI) push $(FULL_IMAGE)

.PHONY: push-tag
push-tag: ## Push a specific tag (usage: make push-tag TAG=v1.0.0)
	@if [ -z "$(TAG)" ]; then \
		echo "Error: TAG variable is required. Usage: make push-tag TAG=v1.0.0"; \
		exit 1; \
	fi
	@echo "Pushing image: $(IMAGE_REPO):$(TAG)"
	$(CONTAINER_CLI) push $(IMAGE_REPO):$(TAG)

.PHONY: build-and-push
build-and-push: build push ## Build and push the image

.PHONY: clean
clean: ## Remove the built image
	@echo "Removing image: $(FULL_IMAGE)"
	$(CONTAINER_CLI) rmi $(FULL_IMAGE) || true

.PHONY: network-join
network-join: ## Ensure the network exists (shared with trader/OTEL)
	@echo "Checking network $(NETWORK_NAME)..."
	@$(CONTAINER_CLI) network inspect $(NETWORK_NAME) >/dev/null 2>&1 || \
		(echo "Network $(NETWORK_NAME) not found. Please run 'make start-otel' or 'make network-create' from the trader directory first." && exit 1)
	@echo "Network $(NETWORK_NAME) is ready"

.PHONY: run
run: network-join ## Run the container locally (usage: make run PORT=9080)
	@echo "Running container: $(FULL_IMAGE)"
	@$(CONTAINER_CLI) rm -f $(IMAGE_NAME) 2>/dev/null || true
	$(CONTAINER_CLI) run -d \
		--name $(IMAGE_NAME) \
		--network $(NETWORK_NAME) \
		-p $(PORT):9080 \
		-p $(DEBUG_PORT):7777 \
		-e LICENSE=accept \
		-e OTEL_EXPORTER_OTLP_ENDPOINT=http://$(OTEL_CONTAINER):4317 \
		$(FULL_IMAGE)
	@echo "Container started. Access at http://localhost:$(PORT)"
	@echo "Debug port available at: $(DEBUG_PORT)"
	@echo "Connected to OpenTelemetry Collector at $(OTEL_CONTAINER):4317"
	@echo "To view logs: make logs"
	@echo "To stop: make stop"

.PHONY: run-it
run-it: network-join ## Run the container interactively (usage: make run-it PORT=9080)
	@echo "Running container interactively: $(FULL_IMAGE)"
	$(CONTAINER_CLI) run -it --rm \
		--name $(IMAGE_NAME) \
		--network $(NETWORK_NAME) \
		-p $(PORT):9080 \
		-p $(DEBUG_PORT):7777 \
		-e LICENSE=accept \
		-e OTEL_EXPORTER_OTLP_ENDPOINT=http://$(OTEL_CONTAINER):4317 \
		$(FULL_IMAGE)

.PHONY: stop
stop: ## Stop the running container
	@echo "Stopping container: $(IMAGE_NAME)"
	$(CONTAINER_CLI) stop $(IMAGE_NAME) || true
	$(CONTAINER_CLI) rm $(IMAGE_NAME) || true

.PHONY: logs
logs: ## View container logs (usage: make logs or make logs FOLLOW=true)
	@if [ "$(FOLLOW)" = "true" ]; then \
		$(CONTAINER_CLI) logs -f $(IMAGE_NAME); \
	else \
		$(CONTAINER_CLI) logs $(IMAGE_NAME); \
	fi

.PHONY: shell
shell: ## Get a shell inside the running container
	@echo "Opening shell in container: $(IMAGE_NAME)"
	$(CONTAINER_CLI) exec -it $(IMAGE_NAME) /bin/bash

.PHONY: restart
restart: stop run ## Restart the container

.PHONY: info
info: ## Display build information
	@echo "Build Configuration:"
	@echo "  Container CLI:  $(CONTAINER_CLI)"
	@echo "  Image Name:     $(IMAGE_NAME)"
	@echo "  Image Tag:      $(IMAGE_TAG)"
	@echo "  Image Registry: $(IMAGE_REGISTRY)"
	@echo "  Full Image:     $(FULL_IMAGE)"
	@echo "  Dockerfile:     $(DOCKERFILE)"
	@echo ""
	@echo "Runtime Configuration:"
	@echo "  HTTP Port:      $(PORT)"
	@echo "  Debug Port:     $(DEBUG_PORT)"
	@echo "  Network:        $(NETWORK_NAME)"
	@echo "  OTEL Collector: $(OTEL_CONTAINER):4317"

# Default port values (different from trader to avoid conflicts)
PORT ?= 9081
DEBUG_PORT ?= 7778

.DEFAULT_GOAL := help
