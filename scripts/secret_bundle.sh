#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STURDY_DIR="${OPENCLAW_STURDY_DIR:-$(cd "$ROOT_DIR/../sturdy-journey" 2>/dev/null && pwd || true)}"

SECRET_BUNDLE="${OPENCLAW_SECRET_BUNDLE:-$ROOT_DIR/secrets/codex.env.age}"
AGE_RECIPIENTS_FILE="${AGE_RECIPIENTS_FILE:-$ROOT_DIR/secrets/age.recipients}"
SECRET_BACKUP_DIR="${OPENCLAW_SECRET_BACKUP_DIR:-$ROOT_DIR/secrets/backups}"
DEFAULT_DATA_ROOT="$ROOT_DIR/.openclaw_data"

CANONICAL_KEYS=(
  ORACLE_API_KEY
  ADMIN_TOKEN
  GATEWAY_TOKEN
  LLM_ARCH_BASE_URL
  CLOUD_ONLY
  OPENCLAW_DATA_DIR
  API_AUTH_MODE
  API_AUTH_ALLOW_EMPTY_KEYS
  WORKFLOW_APPROVAL_MODE
  WORKFLOW_TOKEN_BUDGET
  OLLAMA_BASE_URL
  OPENROUTER_API_KEY
  GROQ_API_KEY
  OPENAI_API_KEY
  ANTHROPIC_API_KEY
  GEMINI_API_KEY
  GOOGLE_API_KEY
  NANOGPT_API_KEY
  VENICE_API_KEY
  VENICE_DIEM_STAKE
  VENICE_CHEAP_MODEL
  VENICE_BASE_MODEL
  VENICE_FRONTIER_MODEL
  VENICE_FRONTIER_REASONING_MODEL
  VENICE_FRONTIER_CODING_MODEL
  VENICE_API_BASE_URL
  VENICE_BURN_ENABLED
  VENICE_DAILY_DIEM_BUDGET
  VENICE_BURN_RESERVE_CREDITS
  VENICE_RESET_HOUR_LOCAL
  VENICE_BURN_FORCE_PROFILE
  VENICE_BURN_FALLBACK_PROFILE
  VENICE_BURN_STATE_FILE
  SIGNAL_ENABLED
  SIGNAL_NUMBER
  SIGNAL_API_URL
  SIGNAL_WHITELIST
)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARNING: $*" >&2
}

ensure_parent() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
}

generate_oracle_key() {
  if command -v openssl >/dev/null 2>&1; then
    echo "llm_$(openssl rand -hex 24)"
  else
    echo "llm_$(date +%s)_$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  fi
}

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    date +%s | shasum | awk '{print $1}'
  fi
}

require_age() {
  command -v age >/dev/null 2>&1 || die "age is required"
}

require_bundle() {
  [[ -f "$SECRET_BUNDLE" ]] || die "missing encrypted bundle: $SECRET_BUNDLE"
}

read_recipients() {
  local recipients=()
  local line=""

  [[ -f "$AGE_RECIPIENTS_FILE" ]] || die "missing recipients file: $AGE_RECIPIENTS_FILE"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    recipients+=("$line")
  done < "$AGE_RECIPIENTS_FILE"

  ((${#recipients[@]} > 0)) || die "no age recipients found in $AGE_RECIPIENTS_FILE"
  printf '%s\n' "${recipients[@]}"
}

decrypt_bundle() {
  require_age
  require_bundle

  local cmd=(age -d)
  if [[ -n "${AGE_IDENTITY_FILE:-}" ]]; then
    cmd+=(-i "$AGE_IDENTITY_FILE")
  fi
  "${cmd[@]}" "$SECRET_BUNDLE"
}

encrypt_stream_to_bundle() {
  require_age
  local tmp_file
  local recipients=()
  local recipient=""
  while IFS= read -r recipient || [[ -n "$recipient" ]]; do
    [[ -z "$recipient" ]] && continue
    recipients+=("$recipient")
  done < <(read_recipients)
  ensure_parent "$SECRET_BUNDLE"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/codex-secret-bundle.XXXXXX.age")"
  trap 'rm -f "$tmp_file"' RETURN

  local cmd=(age)
  for recipient in "${recipients[@]}"; do
    cmd+=(-r "$recipient")
  done

  "${cmd[@]}" -o "$tmp_file"
  mv "$tmp_file" "$SECRET_BUNDLE"
  trap - RETURN
}

backup_bundle() {
  [[ -f "$SECRET_BUNDLE" ]] || return 0
  mkdir -p "$SECRET_BACKUP_DIR"
  cp "$SECRET_BUNDLE" "$SECRET_BACKUP_DIR/codex.env.$(date -u +%Y%m%dT%H%M%SZ).age"
}

stream_value() {
  local key="$1"
  awk -F= -v target="$key" '$1 == target { sub(/^[^=]*=/, ""); print; exit }'
}

set_stream_value() {
  local key="$1"
  local value="$2"
  awk -v k="$key" -v v="$value" '
    BEGIN { found=0 }
    $0 ~ ("^" k "=") { print k "=" v; found=1; next }
    { print }
    END { if (!found) print k "=" v }
  '
}

get_legacy_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  awk -F= -v target="$key" '$1 == target { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

get_legacy_api_key_value() {
  local file="$1"
  local raw
  raw="$(get_legacy_value "$file" "API_KEYS")"
  raw="${raw%%,*}"
  printf '%s' "$raw"
}

resolve_legacy_value() {
  local key="$1"
  local root_env="$ROOT_DIR/.env"
  local infra_env="$ROOT_DIR/infra/.env"
  local agent_env="$ROOT_DIR/agent/config/.env"
  local sturdy_env=""

  if [[ -n "$STURDY_DIR" ]]; then
    sturdy_env="$STURDY_DIR/config/.env"
  fi

  case "$key" in
    ORACLE_API_KEY)
      get_legacy_value "$root_env" "ORACLE_API_KEY" || true
      get_legacy_api_key_value "$infra_env" || true
      get_legacy_value "$agent_env" "ORACLE_API_KEY" || true
      get_legacy_value "$sturdy_env" "ORACLE_API_KEY" || true
      ;;
    ADMIN_TOKEN)
      get_legacy_value "$infra_env" "ADMIN_TOKEN" || true
      get_legacy_value "$root_env" "ADMIN_TOKEN" || true
      ;;
    GATEWAY_TOKEN)
      get_legacy_value "$agent_env" "GATEWAY_TOKEN" || true
      get_legacy_value "$sturdy_env" "GATEWAY_TOKEN" || true
      ;;
    SIGNAL_WHITELIST)
      get_legacy_value "$root_env" "SIGNAL_WHITELIST" || true
      get_legacy_value "$infra_env" "SIGNAL_WHITELIST" || true
      get_legacy_value "$agent_env" "SIGNAL_WHITELIST" || true
      get_legacy_value "$sturdy_env" "SIGNAL_WHITELIST" || true
      get_legacy_value "$agent_env" "SIGNAL_ALLOWED_NUMBERS" || true
      get_legacy_value "$sturdy_env" "SIGNAL_ALLOWED_NUMBERS" || true
      ;;
    GEMINI_API_KEY)
      get_legacy_value "$root_env" "GEMINI_API_KEY" || true
      get_legacy_value "$infra_env" "GEMINI_API_KEY" || true
      get_legacy_value "$agent_env" "GEMINI_API_KEY" || true
      get_legacy_value "$sturdy_env" "GEMINI_API_KEY" || true
      get_legacy_value "$root_env" "GOOGLE_API_KEY" || true
      get_legacy_value "$agent_env" "GOOGLE_API_KEY" || true
      get_legacy_value "$sturdy_env" "GOOGLE_API_KEY" || true
      ;;
    GOOGLE_API_KEY)
      get_legacy_value "$root_env" "GOOGLE_API_KEY" || true
      get_legacy_value "$agent_env" "GOOGLE_API_KEY" || true
      get_legacy_value "$sturdy_env" "GOOGLE_API_KEY" || true
      get_legacy_value "$root_env" "GEMINI_API_KEY" || true
      get_legacy_value "$infra_env" "GEMINI_API_KEY" || true
      get_legacy_value "$agent_env" "GEMINI_API_KEY" || true
      get_legacy_value "$sturdy_env" "GEMINI_API_KEY" || true
      ;;
    *)
      get_legacy_value "$root_env" "$key" || true
      get_legacy_value "$infra_env" "$key" || true
      get_legacy_value "$agent_env" "$key" || true
      get_legacy_value "$sturdy_env" "$key" || true
      ;;
  esac | awk 'NF { print; exit }'
}

canonical_default() {
  local key="$1"
  case "$key" in
    ORACLE_API_KEY)
      generate_oracle_key
      ;;
    ADMIN_TOKEN|GATEWAY_TOKEN)
      generate_token
      ;;
    LLM_ARCH_BASE_URL)
      echo "http://127.0.0.1:8000"
      ;;
    CLOUD_ONLY)
      echo "true"
      ;;
    OPENCLAW_DATA_DIR)
      echo "$DEFAULT_DATA_ROOT"
      ;;
    API_AUTH_MODE)
      echo "required"
      ;;
    API_AUTH_ALLOW_EMPTY_KEYS)
      echo "false"
      ;;
    WORKFLOW_APPROVAL_MODE)
      echo "on-risk"
      ;;
    WORKFLOW_TOKEN_BUDGET)
      echo "6000"
      ;;
    SIGNAL_ENABLED)
      local signal_number
      signal_number="$(resolve_legacy_value SIGNAL_NUMBER || true)"
      if [[ -n "$signal_number" ]]; then
        echo "true"
      fi
      ;;
    SIGNAL_API_URL)
      echo "http://127.0.0.1:8080"
      ;;
    *)
      ;;
  esac
}

canonical_value_from_bundle() {
  local bundle_text="$1"
  local key="$2"
  local value
  value="$(printf '%s\n' "$bundle_text" | stream_value "$key")"
  if [[ -z "$value" ]]; then
    value="$(canonical_default "$key")"
  fi
  printf '%s' "$value"
}

emit_canonical_bundle() {
  local key=""
  local value=""

  for key in "${CANONICAL_KEYS[@]}"; do
    value="$(resolve_legacy_value "$key")"
    if [[ -z "$value" ]]; then
      value="$(canonical_default "$key")"
    fi
    [[ -z "$value" ]] && continue
    printf '%s=%s\n' "$key" "$value"
  done
}

render_key_value() {
  local key="$1"
  local value="$2"
  [[ -z "$value" ]] && return 0
  printf '%s=%s\n' "$key" "$value"
}

render_common_env() {
  local bundle_text="$1"
  local key=""
  local value=""
  for key in "${CANONICAL_KEYS[@]}"; do
    case "$key" in
      OLLAMA_BASE_URL)
        continue
        ;;
    esac
    value="$(canonical_value_from_bundle "$bundle_text" "$key")"
    render_key_value "$key" "$value"
  done
}

render_target_env() {
  local target="$1"
  local bundle_text
  local oracle_key
  local signal_whitelist
  local signal_api_url
  local base_url
  local cloud_only

  bundle_text="$(decrypt_bundle)"
  render_common_env "$bundle_text"

  oracle_key="$(canonical_value_from_bundle "$bundle_text" "ORACLE_API_KEY")"
  signal_whitelist="$(canonical_value_from_bundle "$bundle_text" "SIGNAL_WHITELIST")"
  signal_api_url="$(canonical_value_from_bundle "$bundle_text" "SIGNAL_API_URL")"
  base_url="$(canonical_value_from_bundle "$bundle_text" "LLM_ARCH_BASE_URL")"
  cloud_only="$(canonical_value_from_bundle "$bundle_text" "CLOUD_ONLY")"

  case "$target" in
    infra)
      render_key_value "API_KEYS" "$oracle_key"
      render_key_value "SIGNAL_WHITELIST" "$signal_whitelist"
      if [[ "$cloud_only" != "true" ]]; then
        render_key_value "OLLAMA_BASE_URL" "$(canonical_value_from_bundle "$bundle_text" "OLLAMA_BASE_URL")"
      fi
      ;;
    agent|sturdy)
      render_key_value "ORACLE_BASE_URL" "${base_url%/}/v1"
      render_key_value "SIGNAL_ALLOWED_NUMBERS" "$signal_whitelist"
      render_key_value "OLLAMA_BASE_URL" "$(canonical_value_from_bundle "$bundle_text" "OLLAMA_BASE_URL")"
      ;;
    root)
      render_key_value "OLLAMA_BASE_URL" "$(canonical_value_from_bundle "$bundle_text" "OLLAMA_BASE_URL")"
      ;;
    *)
      die "unsupported target: $target"
      ;;
  esac

  if [[ -n "$signal_whitelist" ]]; then
    render_key_value "SIGNAL_WHITELIST" "$signal_whitelist"
  fi
  if [[ -n "$signal_api_url" ]]; then
    render_key_value "SIGNAL_API_URL" "$signal_api_url"
  fi
}

render_target_shell() {
  local target="$1"
  local line=""
  local key=""
  local value=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    printf 'export %s=%q\n' "$key" "$value"
  done < <(render_target_env "$target")
}

write_target_env() {
  local target="$1"
  local output_path="${2:-}"
  if [[ -n "$output_path" ]]; then
    ensure_parent "$output_path"
    render_target_env "$target" >"$output_path"
    chmod 600 "$output_path"
    return 0
  fi
  render_target_env "$target"
}

seal_bundle() {
  backup_bundle
  emit_canonical_bundle | encrypt_stream_to_bundle
  echo "sealed:$SECRET_BUNDLE"
}

rotate_owned_keys() {
  local bundle_text
  require_bundle
  bundle_text="$(decrypt_bundle)"
  backup_bundle
  bundle_text="$(printf '%s\n' "$bundle_text" | set_stream_value "ORACLE_API_KEY" "$(generate_oracle_key)")"
  bundle_text="$(printf '%s\n' "$bundle_text" | set_stream_value "GATEWAY_TOKEN" "$(generate_token)")"
  bundle_text="$(printf '%s\n' "$bundle_text" | set_stream_value "ADMIN_TOKEN" "$(generate_token)")"
  printf '%s\n' "$bundle_text" | encrypt_stream_to_bundle
  echo "rotated:$SECRET_BUNDLE"
}

usage() {
  cat <<'EOF'
Usage: secret_bundle.sh <command> [args]

Commands:
  render-env <target> [output]   Render a target envfile (root|infra|agent|sturdy)
  render-shell <target>          Render shell-safe export lines for a target
  seal                           Seal current plaintext env sources into codex.env.age
  rotate-owned                   Rotate locally owned credentials in codex.env.age
  decrypt                        Print decrypted bundle contents to stdout
EOF
}

command="${1:-}"
shift || true

case "$command" in
  render-env)
    write_target_env "${1:-root}" "${2:-}"
    ;;
  render-shell)
    render_target_shell "${1:-root}"
    ;;
  seal)
    seal_bundle
    ;;
  rotate-owned)
    rotate_owned_keys
    ;;
  decrypt)
    decrypt_bundle
    ;;
  *)
    usage
    exit 1
    ;;
esac
