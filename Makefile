.PHONY: sync status up down smoke contract-test e2e infra-up infra-down agent-up agent-down prepare submodule-check

SHELL := /bin/bash

sync:
	git submodule sync --recursive
	git submodule update --init --recursive

status:
	@echo "== Submodule status =="
	git submodule status --recursive

# --- Infra (LLM-Architecture) ---
infra-up:
	./bootstrap.sh infra-up

infra-down:
	./bootstrap.sh infra-down

# --- Agent (Fortified OpenClaw deployment) ---
agent-up:
	./bootstrap.sh agent-up

agent-down:
	./bootstrap.sh agent-down

prepare:
	./bootstrap.sh prepare

submodule-check:
	@bad="$$(git submodule status --recursive | grep -E '^[+-U]' || true)"; \
	if [ -n "$$bad" ]; then \
		echo "Submodule pin mismatch detected:"; \
		echo "$$bad"; \
		exit 1; \
	fi

# --- System ---
up:
	./bootstrap.sh up

down:
	./bootstrap.sh down

# --- Tests ---
contract-test:
	./bootstrap.sh contract-test

smoke:
	./bootstrap.sh smoke

e2e:
	python3 e2e/smoke_e2e.py
