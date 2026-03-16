#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
AGENT_DIR="$ROOT_DIR/agent"
ROOT_ENV="$ROOT_DIR/.env"
INFRA_ENV="$INFRA_DIR/.env"
AGENT_ENV="$AGENT_DIR/config/.env"
AGENT_ENV_EXAMPLE="$AGENT_DIR/config/.env.example"
SCAFFOLD_UPGRADE_SCRIPT="$ROOT_DIR/scripts/scaffold_upgrade.py"
SECRET_HELPER="$ROOT_DIR/scripts/secret_bundle.sh"
DEFAULT_DATA_ROOT="$ROOT_DIR/.openclaw_data"
if [[ -x "$INFRA_DIR/venv/bin/python" ]]; then
  INFRA_VENV="$INFRA_DIR/venv"
elif [[ -x "$INFRA_DIR/.venv/bin/python" ]]; then
  INFRA_VENV="$INFRA_DIR/.venv"
else
  INFRA_VENV="$INFRA_DIR/venv"
fi
INFRA_PID_FILE="$ROOT_DIR/.infra.pid"
INFRA_LOG_FILE="$ROOT_DIR/.infra.log"

bootstrap_tmp_dir() {
  export TMPDIR="$ROOT_DIR/.tmp"
  mkdir -p "$TMPDIR"
}

ensure_secret_tooling() {
  [[ -x "$SECRET_HELPER" ]] || die "missing secret helper: $SECRET_HELPER"
}

ensure_secret_bundle() {
  ensure_secret_tooling
  [[ -f "${OPENCLAW_SECRET_BUNDLE:-$ROOT_DIR/secrets/codex.env.age}" ]] || die \
    "missing encrypted secret bundle; run '$ROOT_DIR/bootstrap.sh seal-secrets' first"
  command -v age >/dev/null 2>&1 || die "age is required to decrypt the secret bundle"
}

render_runtime_env() {
  local target="$1"
  local output_path="$2"
  ensure_secret_bundle
  bootstrap_tmp_dir
  "$SECRET_HELPER" render-env "$target" "$output_path"
}

load_rendered_env() {
  local target="$1"
  ensure_secret_bundle
  bootstrap_tmp_dir
  # shellcheck disable=SC1090
  source <("$SECRET_HELPER" render-shell "$target")
}

with_rendered_env_pipe() {
  local target="$1"
  shift
  local fifo
  local render_pid
  local status

  ensure_secret_bundle
  bootstrap_tmp_dir
  fifo="$(mktemp -u "$TMPDIR/${target}.env.XXXXXX")"
  mkfifo "$fifo"
  "$SECRET_HELPER" render-env "$target" >"$fifo" &
  render_pid=$!
  "$@" "$fifo"
  status=$?
  wait "$render_pid"
  rm -f "$fifo"
  return "$status"
}

seal_secrets() {
  ensure_secret_tooling
  bootstrap_tmp_dir
  "$SECRET_HELPER" seal
}

rotate_owned_keys() {
  ensure_secret_tooling
  bootstrap_tmp_dir
  "$SECRET_HELPER" rotate-owned
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

pid_is_running() {
  local pid="$1"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

is_oracle_infra_pid() {
  local pid="$1"
  local cmd
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ -n "$cmd" ]]; then
    [[ "$cmd" == *"uvicorn"* && "$cmd" == *"src.api.server:app"* ]]
    return $?
  fi
  # Fallback when process metadata is restricted: trust active listener on infra port.
  lsof -nP -a -p "$pid" -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1
}

discover_oracle_infra_pid() {
  local pid
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    if pid_is_running "$pid" && is_oracle_infra_pid "$pid"; then
      echo "$pid"
      return 0
    fi
  done < <(lsof -tiTCP:8000 -sTCP:LISTEN 2>/dev/null || true)
  return 1
}

adopt_oracle_infra_pid_if_running() {
  local pid
  pid="$(discover_oracle_infra_pid || true)"
  if [[ -n "$pid" ]]; then
    echo "$pid" >"$INFRA_PID_FILE"
    return 0
  fi
  return 1
}

compose_cmd() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return 0
  fi
  echo "ERROR: docker compose not found (need docker-compose or docker compose)." >&2
  exit 1
}

generate_oracle_key() {
  if command -v openssl >/dev/null 2>&1; then
    echo "llm_$(openssl rand -hex 24)"
  else
    echo "llm_$(date +%s)_$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  fi
}

upsert_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp_file
  tmp_file="$(mktemp /tmp/bootstrap.XXXXXX)"
  awk -v k="$key" -v v="$value" '
    BEGIN { found=0 }
    $0 ~ ("^" k "=") { print k "=" v; found=1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "$file" >"$tmp_file"
  cat "$tmp_file" > "$file"
  rm "$tmp_file"
}

remove_env_key() {
  local file="$1"
  local key="$2"
  local tmp_file

  [[ -f "$file" ]] || return 0

  tmp_file="$(mktemp /tmp/bootstrap.XXXXXX)"
  awk -v k="$key" '$0 !~ ("^" k "=") { print }' "$file" >"$tmp_file"
  cat "$tmp_file" >"$file"
  rm "$tmp_file"
}

env_file_value() {
  local file="$1"
  local key="$2"

  [[ -f "$file" ]] || return 0
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print }' "$file" | tail -n 1 || true
}

adopt_env_value() {
  local file="$1"
  local key="$2"
  local value="${!key:-}"

  if [[ -z "$value" ]]; then
    value="$(env_file_value "$file" "$key")"
  fi

  if [[ -n "$value" ]]; then
    printf -v "$key" '%s' "$value"
    export "${key?}"
  fi
}

ensure_root_env() {
  load_rendered_env root
}

ensure_infra_env() {
  ensure_secret_bundle
}

ensure_agent_env() {
  ensure_secret_bundle
}

sync_submodules() {
  git -C "$ROOT_DIR" submodule sync --recursive
  local dirty_paths
  dirty_paths="$(submodule_dirty_paths)"
  if strict_submodule_pins_enabled; then
    if [[ -n "$dirty_paths" ]]; then
      echo "ERROR: STRICT_SUBMODULE_PINS is enabled and submodules are dirty:" >&2
      while IFS= read -r path; do
        [[ -n "$path" ]] && echo "  - $path" >&2
      done <<< "$dirty_paths"
      echo "Commit/stash submodule changes or disable STRICT_SUBMODULE_PINS for local dev." >&2
      exit 1
    fi
    git -C "$ROOT_DIR" submodule update --init --recursive
    return 0
  fi

  if [[ -n "$dirty_paths" ]]; then
    echo "Skipping submodule update due local changes in:" >&2
    while IFS= read -r path; do
      [[ -n "$path" ]] && echo "  - $path" >&2
    done <<< "$dirty_paths"
    return 0
  fi
  git -C "$ROOT_DIR" submodule update --init --recursive
}

submodule_dirty_paths() {
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ -n "$(git -C "$ROOT_DIR/$path" status --short 2>/dev/null || true)" ]]; then
      echo "$path"
    fi
  done < <(git -C "$ROOT_DIR" config --file .gitmodules --get-regexp path | awk '{print $2}')
}

truthy() {
  local value="${1:-}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

strict_submodule_pins_enabled() {
  if truthy "${STRICT_SUBMODULE_PINS:-}"; then
    return 0
  fi
  if truthy "${CI:-}"; then
    return 0
  fi
  return 1
}

verify_submodule_pins() {
  if strict_submodule_pins_enabled; then
    local strict_bad
    strict_bad="$(git -C "$ROOT_DIR" submodule status --recursive | grep -E '^[+-U]' || true)"
    if [[ -n "$strict_bad" ]]; then
      echo "ERROR: STRICT_SUBMODULE_PINS failed; submodule pins do not match committed SHAs:" >&2
      echo "$strict_bad" >&2
      exit 1
    fi
    return 0
  fi

  local dirty_paths
  dirty_paths="$(submodule_dirty_paths)"
  if [[ -n "$dirty_paths" ]]; then
    echo "Skipping submodule pin verification due local changes in:" >&2
    while IFS= read -r path; do
      [[ -n "$path" ]] && echo "  - $path" >&2
    done <<< "$dirty_paths"
    return 0
  fi

  local bad
  bad="$(git -C "$ROOT_DIR" submodule status --recursive | grep -E '^[+-U]' || true)"
  if [[ -n "$bad" ]]; then
    echo "ERROR: submodules are not pinned to committed SHAs:" >&2
    echo "$bad" >&2
    exit 1
  fi
}

install_infra_deps() {
  if [[ ! -d "$INFRA_VENV" ]]; then
    python3 -m venv "$INFRA_VENV"
  fi
  "$INFRA_VENV/bin/python" -m pip install --upgrade pip >/dev/null
  "$INFRA_VENV/bin/pip" install -r "$INFRA_DIR/requirements.txt"
}

launch_detached_infra() {
  local uvicorn_bin="$1"
  INFRA_UVICORN_BIN="$uvicorn_bin" \
  INFRA_WORKDIR="$INFRA_DIR" \
  INFRA_LOG_TARGET="$INFRA_LOG_FILE" \
  python3 - <<'PY'
import os
import subprocess

cmd = [
    os.environ["INFRA_UVICORN_BIN"],
    "src.api.server:app",
    "--host",
    "127.0.0.1",
    "--port",
    "8000",
]

with open(os.environ["INFRA_LOG_TARGET"], "ab", buffering=0) as log_handle:
    proc = subprocess.Popen(
        cmd,
        cwd=os.environ["INFRA_WORKDIR"],
        env=os.environ.copy(),
        stdin=subprocess.DEVNULL,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )

print(proc.pid)
PY
}

wait_for_infra() {
  local attempts=60
  while (( attempts > 0 )); do
    if curl -fsS "http://127.0.0.1:8000/docs" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    attempts=$((attempts - 1))
  done
  return 1
}

start_infra() {
  if [[ -f "$INFRA_PID_FILE" ]]; then
    local existing_pid
    existing_pid="$(cat "$INFRA_PID_FILE" 2>/dev/null || true)"
    if pid_is_running "$existing_pid" && is_oracle_infra_pid "$existing_pid"; then
      echo "Infra already running (pid: $existing_pid)"
      return 0
    fi
    rm -f "$INFRA_PID_FILE"
  fi

  if adopt_oracle_infra_pid_if_running; then
    local adopted_pid
    adopted_pid="$(cat "$INFRA_PID_FILE")"
    echo "Adopted existing infra process (pid: $adopted_pid)"
    return 0
  fi

  local launched_pid
  launched_pid="$(
    cd "$INFRA_DIR"
    # shellcheck disable=SC1090
    source <("$SECRET_HELPER" render-shell infra)
    mkdir -p "${OPENCLAW_DATA_DIR:-$DEFAULT_DATA_ROOT}"
    launch_detached_infra "$INFRA_VENV/bin/uvicorn"
  )"
  printf '%s\n' "$launched_pid" >"$INFRA_PID_FILE"

  # Catch immediate bind/crash failure before readiness loop.
  sleep 1
  if ! pid_is_running "$launched_pid"; then
    echo "ERROR: infra process exited immediately (pid: $launched_pid)." >&2
    tail -n 80 "$INFRA_LOG_FILE" >&2 || true
    rm -f "$INFRA_PID_FILE"
    exit 1
  fi

  if ! wait_for_infra; then
    echo "ERROR: infra did not become ready. Tail of $INFRA_LOG_FILE:" >&2
    tail -n 80 "$INFRA_LOG_FILE" >&2 || true
    rm -f "$INFRA_PID_FILE"
    exit 1
  fi

  if ! pid_is_running "$launched_pid"; then
    # Another valid process may own :8000; adopt if it's Oracle, otherwise fail.
    if adopt_oracle_infra_pid_if_running; then
      local adopted_pid
      adopted_pid="$(cat "$INFRA_PID_FILE")"
      echo "Infra ready at http://127.0.0.1:8000 (adopted pid: $adopted_pid)"
      return 0
    fi
    echo "ERROR: infra became reachable but launched pid is not running." >&2
    rm -f "$INFRA_PID_FILE"
    exit 1
  fi

  echo "Infra ready at http://127.0.0.1:8000"
}

stop_infra() {
  local pid=""
  if [[ -f "$INFRA_PID_FILE" ]]; then
    pid="$(cat "$INFRA_PID_FILE" 2>/dev/null || true)"
    if ! (pid_is_running "$pid" && is_oracle_infra_pid "$pid"); then
      pid=""
      rm -f "$INFRA_PID_FILE"
    fi
  fi

  if [[ -z "$pid" ]]; then
    pid="$(discover_oracle_infra_pid || true)"
    if [[ -n "$pid" ]]; then
      echo "$pid" >"$INFRA_PID_FILE"
    fi
  fi

  if [[ -z "$pid" ]]; then
    echo "Infra not running"
    return 0
  fi

  if pid_is_running "$pid"; then
    kill "$pid"
    for _ in {1..10}; do
      if ! pid_is_running "$pid"; then
        break
      fi
      sleep 1
    done
    if pid_is_running "$pid"; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    echo "Stopped infra (pid: $pid)"
  fi
  rm -f "$INFRA_PID_FILE"
}

start_agent() {
  local compose
  compose="$(compose_cmd)"
  with_rendered_env_pipe agent bash -lc '
    compose="$1"
    env_file="$2"
    cd "'"$AGENT_DIR"'/docker"
    # shellcheck disable=SC2086
    $compose --env-file "$env_file" -f docker-compose.yml up -d --remove-orphans
  ' _ "$compose"
}

stop_agent() {
  local compose
  compose="$(compose_cmd)"
  with_rendered_env_pipe agent bash -lc '
    compose="$1"
    env_file="$2"
    cd "'"$AGENT_DIR"'/docker"
    # shellcheck disable=SC2086
    $compose --env-file "$env_file" -f docker-compose.yml down --remove-orphans
  ' _ "$compose"
}

run_contract_test() {
  (
    cd "$ROOT_DIR"
    python3 contract-tests/contract_test_openai_compat.py
  )
}

run_e2e_smoke() {
  (
    cd "$ROOT_DIR"
    python3 e2e/smoke_e2e.py
  )
}

run_smoke() {
  prepare
  start_agent
  start_infra
  run_contract_test
  run_e2e_smoke
}

run_upgrade() {
  local mode="apply"
  local lane=""
  local approve_flag=""
  local passthrough=()

  while (($# > 0)); do
    case "$1" in
      --check)
        mode="check"
        ;;
      --approve)
        approve_flag="--approve"
        ;;
      --lane)
        shift
        if (($# == 0)); then
          echo "ERROR: --lane requires a value" >&2
          exit 1
        fi
        lane="$1"
        ;;
      *)
        passthrough+=("$1")
        ;;
    esac
    shift || true
  done

  if [[ ! -f "$SCAFFOLD_UPGRADE_SCRIPT" ]]; then
    echo "ERROR: missing scaffold upgrade runner: $SCAFFOLD_UPGRADE_SCRIPT" >&2
    exit 1
  fi

  local cmd=(python3 "$SCAFFOLD_UPGRADE_SCRIPT" "$mode")
  if [[ -n "$lane" ]]; then
    cmd+=(--lane "$lane")
  fi
  if [[ -n "$approve_flag" ]]; then
    cmd+=("$approve_flag")
  fi
  if ((${#passthrough[@]} > 0)); then
    cmd+=("${passthrough[@]}")
  fi
  (
    cd "$ROOT_DIR"
    "${cmd[@]}"
  )
}

prepare() {
  ensure_root_env
  ensure_agent_env
  ensure_infra_env
  sync_submodules
  verify_submodule_pins
  install_infra_deps
}

up_all() {
  prepare
  start_agent
  start_infra
  run_contract_test
}

down_all() {
  stop_agent
  stop_infra
}

action="${1:-up}"
shift || true
case "$action" in
  prepare) prepare ;;
  upgrade) run_upgrade "$@" ;;
  render-runtime-env)
    target="${1:-}"
    output_path="${2:-}"
    [[ -n "$target" && -n "$output_path" ]] || die "Usage: $0 render-runtime-env <target> <output-path>"
    render_runtime_env "$target" "$output_path"
    ;;
  seal-secrets) seal_secrets ;;
  rotate-keys) rotate_owned_keys ;;
  infra-up) prepare; start_infra ;;
  infra-down) stop_infra ;;
  agent-up) prepare; start_agent ;;
  agent-down) stop_agent ;;
  contract-test) ensure_root_env; ensure_infra_env; install_infra_deps; start_infra; run_contract_test ;;
  smoke) run_smoke ;;
  up) up_all ;;
  down) down_all ;;
  *)
    echo "Usage: $0 {prepare|upgrade [--check] [--approve] [--lane <name>]|render-runtime-env <target> <output>|seal-secrets|rotate-keys|infra-up|infra-down|agent-up|agent-down|contract-test|smoke|up|down}" >&2
    exit 1
    ;;
esac
