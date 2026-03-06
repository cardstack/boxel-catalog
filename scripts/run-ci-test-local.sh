#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run catalog tests locally against a boxel monorepo checkout using CI-like steps.

Usage:
  scripts/run-ci-test-local.sh [options]

Options:
  --filter <text>       Ember test filter (default: Integration | Catalog | runner)
  -h, --help            Show this help

Environment variables:
  BOXEL_DIR             Monorepo path (default: ./boxel)
  BOXEL_REF             Monorepo git ref (default: get-catalog-to-run-test)
  KEEP_RUNNING          true|false (default: false)
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

run_pnpm() {
  if [ -n "${VOLTA_BIN:-}" ] && [ -x "$VOLTA_BIN" ]; then
    if [ -n "${VOLTA_PNPM_VERSION:-}" ]; then
      VOLTA_FEATURE_PNPM=1 "$VOLTA_BIN" run --pnpm "$VOLTA_PNPM_VERSION" -- pnpm "$@"
    else
      VOLTA_FEATURE_PNPM=1 "$VOLTA_BIN" run -- pnpm "$@"
    fi
  elif command -v volta >/dev/null 2>&1; then
    if [ -n "${VOLTA_PNPM_VERSION:-}" ]; then
      VOLTA_FEATURE_PNPM=1 volta run --pnpm "$VOLTA_PNPM_VERSION" -- pnpm "$@"
    else
      VOLTA_FEATURE_PNPM=1 volta run -- pnpm "$@"
    fi
  else
    pnpm "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BOXEL_DIR="${BOXEL_DIR:-$CATALOG_DIR/boxel}"
BOXEL_REF="${BOXEL_REF:-get-catalog-to-run-test}"
TEST_FILTER="${TEST_FILTER:-Integration | Catalog | runner}"
KEEP_RUNNING="${KEEP_RUNNING:-false}"
VOLTA_BIN="${VOLTA_BIN:-$HOME/.volta/bin/volta}"
VOLTA_PNPM_VERSION=""
if [ ! -x "$VOLTA_BIN" ]; then
  VOLTA_BIN="$(command -v volta 2>/dev/null || true)"
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --filter)
      TEST_FILTER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd git
require_cmd rsync
require_cmd curl
require_cmd node
if ! command -v pnpm >/dev/null 2>&1 && ! command -v volta >/dev/null 2>&1; then
  echo "Missing required command: pnpm (or volta with pnpm support)" >&2
  exit 1
fi

if [ ! -d "$BOXEL_DIR/.git" ]; then
  echo "[local-ci] Expected monorepo checkout at $BOXEL_DIR (missing .git)" >&2
  echo "[local-ci] Clone with: git clone https://github.com/cardstack/boxel \"$BOXEL_DIR\"" >&2
  exit 1
fi

if command -v node >/dev/null 2>&1; then
  VOLTA_PNPM_VERSION="$(
    node -e "const p=require(process.argv[1]);const pm=(p.packageManager||'').match(/^pnpm@(.+)$/);if(pm){process.stdout.write(pm[1]);process.exit(0);}const e=(p.engines&&p.engines.pnpm)||'';if(e)process.stdout.write(String(e));" \
      "$BOXEL_DIR/package.json" 2>/dev/null || true
  )"
fi

echo "[local-ci] Using monorepo: $BOXEL_DIR"
echo "[local-ci] Checking out ref: $BOXEL_REF"
git -C "$BOXEL_DIR" fetch origin "$BOXEL_REF"
git -C "$BOXEL_DIR" checkout -B "$BOXEL_REF" FETCH_HEAD >/dev/null 2>&1

echo "[local-ci] Syncing catalog-realm content"
(
  cd "$BOXEL_DIR/packages/catalog-realm"
  find . -mindepth 1 \
    ! -name '.gitignore' \
    ! -name 'tsconfig.json' \
    ! -name 'package.json' \
    ! -name '.realm.json' \
    ! -path './Spec' \
    ! -path './Spec/*' \
    ! -path './fields' \
    ! -path './fields/*' \
    ! -path './components' \
    ! -path './components/*' \
    ! -path './commands' \
    ! -path './commands/suggest-avatar.gts' \
    ! -path './utils' \
    ! -path './utils/*' \
    ! -path './resources' \
    ! -path './resources/*' \
    ! -path './catalog-app' \
    ! -path './catalog-app/*' \
    ! -name '.' \
    -exec rm -rf {} + 2>/dev/null || true
)

rsync -a \
  --exclude='tsconfig.json' \
  --exclude='package.json' \
  --exclude='.realm.json' \
  --exclude='.gitignore' \
  --exclude='boxel/' \
  --exclude='.vscode/' \
  --exclude='.claude/' \
  --exclude='.git/' \
  --exclude='tests/' \
  "$CATALOG_DIR/" \
  "$BOXEL_DIR/packages/catalog-realm/"

echo "[local-ci] Syncing host tests from catalog repo"
rm -rf "$BOXEL_DIR/packages/host/tests/integration"
rm -rf "$BOXEL_DIR/packages/host/tests/acceptance"
mkdir -p "$BOXEL_DIR/packages/host/tests/integration"
mkdir -p "$BOXEL_DIR/packages/host/tests/acceptance"
cp -r "$CATALOG_DIR/tests/acceptance/"* "$BOXEL_DIR/packages/host/tests/acceptance"
cp -r "$CATALOG_DIR/tests/integration/"* "$BOXEL_DIR/packages/host/tests/integration"
cp -r "$CATALOG_DIR/tests/helpers/"* "$BOXEL_DIR/packages/host/tests/helpers"

# Keep runner harness from monorepo ref and only inject this module.
git -C "$BOXEL_DIR" checkout -- packages/host/tests/integration/catalog/setup.gts
git -C "$BOXEL_DIR" checkout -- packages/host/tests/integration/catalog/catalog-runner-test.gts
mkdir -p "$BOXEL_DIR/packages/host/tests/integration/catalog/generated"
cp \
  "$CATALOG_DIR/tests/integration/catalog/modules/daily-report-dashboard.module.gts" \
  "$BOXEL_DIR/packages/host/tests/integration/catalog/generated/test-module.gts"

cp \
  "$CATALOG_DIR/scripts/test-wait-for-servers.sh" \
  "$BOXEL_DIR/packages/host/scripts/test-wait-for-servers.sh"

SERVICE_SCRIPT="$BOXEL_DIR/packages/realm-server/scripts/start-services-for-host-tests.sh"
if [ ! -f "$SERVICE_SCRIPT" ]; then
  echo "[local-ci] Missing service script: $SERVICE_SCRIPT" >&2
  exit 1
fi
if ! grep -q '^KEEP_FOLDERS=' "$SERVICE_SCRIPT"; then
  echo "[local-ci] Expected KEEP_FOLDERS in: $SERVICE_SCRIPT" >&2
  exit 1
fi
LC_ALL=C perl -0pi -e 's/^KEEP_FOLDERS=.*$/KEEP_FOLDERS="fields catalog-app components commands daily-report-dashboard"/m' "$SERVICE_SCRIPT"
if ! grep -q 'daily-report-dashboard' "$SERVICE_SCRIPT"; then
  echo "[local-ci] Failed to patch KEEP_FOLDERS in: $SERVICE_SCRIPT" >&2
  exit 1
fi
echo "[local-ci] $(grep '^KEEP_FOLDERS=' "$SERVICE_SCRIPT")"

echo "[local-ci] Installing monorepo dependencies"
run_pnpm -C "$BOXEL_DIR" install --frozen-lockfile

echo "[local-ci] Building common dependencies"
run_pnpm -C "$BOXEL_DIR" run build-common-deps

echo "[local-ci] Building host"
(cd "$BOXEL_DIR/packages/host" && NODE_OPTIONS='--max-old-space-size=8192' run_pnpm build)

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/catalog-local-ci.XXXXXX")"
PIDS=()

cleanup() {
  if [ "$KEEP_RUNNING" = "true" ]; then
    echo "[local-ci] keep-running enabled; logs: $LOG_DIR"
    return
  fi

  for pid in "${PIDS[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  wait >/dev/null 2>&1 || true
  rm -rf "$LOG_DIR"
}
trap cleanup EXIT INT TERM

wait_for_http() {
  local url="$1"
  local timeout_secs="$2"
  local started
  started="$(date +%s)"

  until curl -fsS "$url" >/dev/null 2>&1; do
    sleep 2
    if [ $(( $(date +%s) - started )) -ge "$timeout_secs" ]; then
      echo "[local-ci] Timed out waiting for: $url" >&2
      return 1
    fi
  done
}

echo "[local-ci] Starting boxel-icons server"
(cd "$BOXEL_DIR/packages/boxel-icons" && run_pnpm serve >"$LOG_DIR/boxel-icons.log" 2>&1) &
PIDS+=("$!")

echo "[local-ci] Starting host dist server"
(cd "$BOXEL_DIR/packages/host" && run_pnpm serve:dist >"$LOG_DIR/host-dist.log" 2>&1) &
PIDS+=("$!")

echo "[local-ci] Starting realm services for host tests"
(cd "$BOXEL_DIR/packages/realm-server" && run_pnpm start:services-for-host-tests >"$LOG_DIR/realm-services.log" 2>&1) &
PIDS+=("$!")

echo "[local-ci] Waiting for services"
wait_for_http "http://localhost:4200" 900
wait_for_http "http://localhost:4201/base/_readiness-check?acceptHeader=application%2Fvnd.api%2Bjson" 900
wait_for_http "http://localhost:4201/catalog/_readiness-check?acceptHeader=application%2Fvnd.api%2Bjson" 900
wait_for_http "http://localhost:4201/skills/_readiness-check?acceptHeader=application%2Fvnd.api%2Bjson" 900
wait_for_http "http://localhost:4202/node-test/_readiness-check?acceptHeader=application%2Fvnd.api%2Bjson" 900
wait_for_http "http://localhost:4202/test/_readiness-check?acceptHeader=application%2Fvnd.api%2Bjson" 900
wait_for_http "http://localhost:8008" 900
wait_for_http "http://localhost:5001" 900

echo "[local-ci] Registering realm users"
run_pnpm -C "$BOXEL_DIR/packages/matrix" run register-realm-users

run_host_test() {
  local filter="$1"
  if [ -n "${VOLTA_BIN:-}" ] && [ -x "$VOLTA_BIN" ]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
      if [ -n "${VOLTA_PNPM_VERSION:-}" ]; then
        (cd "$BOXEL_DIR/packages/host" && dbus-run-session -- env VOLTA_FEATURE_PNPM=1 "$VOLTA_BIN" run --pnpm "$VOLTA_PNPM_VERSION" -- pnpm exec ember exam --path ./dist --filter="$filter")
      else
        (cd "$BOXEL_DIR/packages/host" && dbus-run-session -- env VOLTA_FEATURE_PNPM=1 "$VOLTA_BIN" run -- pnpm exec ember exam --path ./dist --filter="$filter")
      fi
    else
      if [ -n "${VOLTA_PNPM_VERSION:-}" ]; then
        (cd "$BOXEL_DIR/packages/host" && env VOLTA_FEATURE_PNPM=1 "$VOLTA_BIN" run --pnpm "$VOLTA_PNPM_VERSION" -- pnpm exec ember exam --path ./dist --filter="$filter")
      else
        (cd "$BOXEL_DIR/packages/host" && env VOLTA_FEATURE_PNPM=1 "$VOLTA_BIN" run -- pnpm exec ember exam --path ./dist --filter="$filter")
      fi
    fi
  elif command -v dbus-run-session >/dev/null 2>&1; then
    (cd "$BOXEL_DIR/packages/host" && dbus-run-session -- pnpm exec ember exam --path ./dist --filter="$filter")
  else
    (cd "$BOXEL_DIR/packages/host" && pnpm exec ember exam --path ./dist --filter="$filter")
  fi
}

echo "[local-ci] Running host tests with filter: $TEST_FILTER"
run_host_test "$TEST_FILTER"

echo "[local-ci] Completed successfully"
