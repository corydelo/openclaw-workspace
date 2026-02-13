.PHONY: sync status up down contract-test e2e infra-up infra-down agent-up agent-down

sync:
	git submodule sync --recursive
	git submodule update --init --recursive

status:
	@echo "== Submodule status =="
	git submodule status --recursive

# --- Infra (LLM-Architecture) ---
infra-up:
	cd infra && python3 -m venv venv && . venv/bin/activate && pip install -r requirements.txt
	cd infra && . venv/bin/activate && uvicorn src.api.server:app --host 127.0.0.1 --port 8000

infra-down:
	@echo "Stop infra: press Ctrl+C in the terminal running uvicorn (or implement pkill later)."

# --- Agent (Fortified OpenClaw deployment) ---
agent-up:
	cd agent/docker && docker-compose up -d

agent-down:
	cd agent/docker && docker-compose down

# --- System ---
up: agent-up
	@echo "NOTE: infra-up runs in the foreground. Run it in another terminal: make infra-up"

down: agent-down
	@echo "NOTE: stop infra with Ctrl+C in its terminal (or implement infra-down later)."

# --- Tests ---
contract-test:
	python3 contract-tests/contract_test_openai_compat.py

e2e:
	python3 e2e/smoke_e2e.py
