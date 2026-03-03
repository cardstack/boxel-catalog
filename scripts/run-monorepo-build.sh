#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOXEL_ROOT="${CATALOG_ROOT}/.boxel"
BOXEL_REPO_URL="https://github.com/cardstack/boxel.git"
BOXEL_REF="main"

echo "[0/5] Sync boxel monorepo snapshot (${BOXEL_REF})"
TMP_CLONE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boxel-sync.XXXXXX")"
trap 'rm -rf "${TMP_CLONE_DIR}"' EXIT

git clone --depth 1 --branch "${BOXEL_REF}" "${BOXEL_REPO_URL}" "${TMP_CLONE_DIR}/repo"
mkdir -p "${BOXEL_ROOT}"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='node_modules/' \
  "${TMP_CLONE_DIR}/repo/" \
  "${BOXEL_ROOT}/"

# Treat .boxel as generated build output, not a nested git repository.
rm -rf "${BOXEL_ROOT}/.git"

if [[ ! -d "${BOXEL_ROOT}/packages/catalog-realm" ]]; then
  echo "Could not find boxel monorepo at ${BOXEL_ROOT}" >&2
  echo "Expected: ${BOXEL_ROOT}/packages/catalog-realm" >&2
  exit 1
fi

if [[ ! -d "${CATALOG_ROOT}/tests" ]]; then
  echo "Could not find ${CATALOG_ROOT}/tests" >&2
  exit 1
fi

echo "[1/5] Sync catalog files into monorepo"
(
  cd "${BOXEL_ROOT}/packages/catalog-realm"
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
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='.boxel/' \
  --exclude='node_modules/' \
  --exclude='tsconfig.json' \
  --exclude='package.json' \
  --exclude='.realm.json' \
  --exclude='.gitignore' \
  --exclude='tests/' \
  "${CATALOG_ROOT}/" \
  "${BOXEL_ROOT}/packages/catalog-realm/"

echo "[2/5] Sync catalog tests into host tests"
rm -rf "${BOXEL_ROOT}/packages/host/tests/integration"
rm -rf "${BOXEL_ROOT}/packages/host/tests/acceptance"
mkdir -p "${BOXEL_ROOT}/packages/host/tests/integration"
mkdir -p "${BOXEL_ROOT}/packages/host/tests/acceptance"
cp -r "${CATALOG_ROOT}/tests/acceptance/." "${BOXEL_ROOT}/packages/host/tests/acceptance/"
cp -r "${CATALOG_ROOT}/tests/integration/." "${BOXEL_ROOT}/packages/host/tests/integration/"
cp -r "${CATALOG_ROOT}/tests/helpers/." "${BOXEL_ROOT}/packages/host/tests/helpers/"
cp "${CATALOG_ROOT}/scripts/test-wait-for-servers.sh" "${BOXEL_ROOT}/packages/host/scripts/test-wait-for-servers.sh"

echo "[3/5] Ensure monorepo dependencies are installed"
(
  cd "${BOXEL_ROOT}"
  if [[ ! -d node_modules || ! -x node_modules/.bin/concurrently ]]; then
    pnpm install --frozen-lockfile
  else
    echo "Dependencies already installed"
  fi
)

echo "[4/5] Build type declarations for dependencies"
(
  cd "${BOXEL_ROOT}/packages/boxel-icons"
  pnpm run build:types
)
(
  cd "${BOXEL_ROOT}/packages/boxel-ui/addon"
  pnpm run build:types
)

echo "[5/5] Done"
