#!/bin/sh
# Copies boxel-catalog source files into the boxel monorepo's packages/catalog/contents.
#
# Usage (run from monorepo root):
#   sh boxel-catalog-src/scripts/copy-catalog-to-monorepo.sh

set -eu

CATALOG_SRC="boxel-catalog-src"
CATALOG_REALM="packages/catalog/contents"

echo "[copy-catalog] Removing existing catalog content (keeping config files)..."
mkdir -p "$CATALOG_REALM"
cd "$CATALOG_REALM"
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
  ! -path './commands/*' \
  ! -path './utils' \
  ! -path './utils/*' \
  ! -path './resources' \
  ! -path './resources/*' \
  ! -path './catalog-app' \
  ! -path './catalog-app/*' \
  ! -name '.' \
  -exec rm -rf {} + 2>/dev/null || true
cd ../../..

echo "[copy-catalog] Syncing catalog source into monorepo..."
rsync -av \
  --exclude='.git/' \
  --include='index.json' \
  --exclude='*.json' \
  --exclude='.gitignore' \
  --exclude='tests/' \
  --exclude='scripts/' \
  --exclude='system-card/' \
  "$CATALOG_SRC/" "$CATALOG_REALM/"

echo "[copy-catalog] Done."
