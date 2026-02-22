.PHONY: sync status up down smoke contract-test e2e infra-up infra-down agent-up agent-down prepare submodule-check agent-drift-check venice-models preflight factory-loop

SHELL := /bin/bash

sync:
	git submodule sync --recursive
	git submodule update --init --recursive

status:
	@echo "== Submodule status =="
	git submodule status --recursive

# --- Infra (LLM-Architecture) ---
infra-up:
	bash ./bootstrap.sh infra-up

infra-down:
	bash ./bootstrap.sh infra-down

# --- Agent (Fortified OpenClaw deployment) ---
agent-up:
	bash ./bootstrap.sh agent-up

agent-down:
	bash ./bootstrap.sh agent-down

prepare:
	bash ./bootstrap.sh prepare

submodule-check:
	@bad="$$(git submodule status --recursive | grep -E '^[+-U]' || true)"; \
	if [ -n "$$bad" ]; then \
		echo "Submodule pin mismatch detected:"; \
		echo "$$bad"; \
		exit 1; \
	fi

agent-drift-check:
	@agent_remote="$$(git -C agent config --get remote.origin.url 2>/dev/null || echo "missing")"; \
	canonical_remote="$$(git -C ../sturdy-journey config --get remote.origin.url 2>/dev/null || echo "missing")"; \
	agent_sha="$$(git -C agent rev-parse --short HEAD 2>/dev/null || echo "missing")"; \
	canonical_sha="$$(git -C ../sturdy-journey rev-parse --short HEAD 2>/dev/null || echo "missing")"; \
	echo "AGENT_REMOTE: $$agent_remote"; \
	echo "CANONICAL_REMOTE: $$canonical_remote"; \
	echo "AGENT_SHA: $$agent_sha"; \
	echo "CANONICAL_SHA: $$canonical_sha"; \
	if [ "$$agent_remote" = "missing" ] || [ "$$canonical_remote" = "missing" ]; then \
		echo "AGENT_DRIFT: UNKNOWN_MISSING_REPO"; \
		exit 1; \
	fi; \
	if [ "$$agent_remote" != "$$canonical_remote" ]; then \
		echo "AGENT_DRIFT: REMOTE_MISMATCH"; \
		exit 1; \
	fi; \
	if [ "$$agent_sha" = "$$canonical_sha" ]; then \
		echo "AGENT_DRIFT: IN_SYNC"; \
		exit 0; \
	fi; \
	echo "AGENT_DRIFT: DIVERGED"; \
	exit 2

# --- System ---
up:
	bash ./bootstrap.sh up

down:
	bash ./bootstrap.sh down

# --- Tests ---
contract-test:
	LLM_ARCH_BASE_URL="$${LLM_ARCH_BASE_URL:-http://127.0.0.1:8000}" python3 contract-tests/contract_test_openai_compat.py

smoke:
	bash ./bootstrap.sh smoke

e2e:
	python3 e2e/smoke_e2e.py

venice-models:
	bash ./infra/scripts/list-venice-models.sh text

preflight:
	./scripts/preflight.sh

factory-loop:
	cd infra && python3 -m src.agents.factory_loop --tasks ../tasks/tasks.json
