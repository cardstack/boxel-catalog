#!/bin/sh
# Copies boxel-catalog source files into the boxel monorepo's catalog-realm.
#
# Usage (run from monorepo root):
#   sh boxel-catalog-src/scripts/copy-catalog-to-monorepo.sh

set -eu

CATALOG_SRC="boxel-catalog-src"
CATALOG_REALM="packages/catalog-realm"

echo "[copy-catalog] Removing existing catalog-realm content (keeping config files)..."
cd "$CATALOG_REALM"
find . -mindepth 1 \
  ! -name '.gitignore' \
  ! -name 'tsconfig.json' \
  ! -name 'package.json' \
  ! -name '.realm.json' \
  ! -name '.' \
  -exec rm -rf {} + 2>/dev/null || true
cd ../..

echo "[copy-catalog] Syncing catalog source into monorepo..."
rsync -av \
  --exclude='tsconfig.json' \
  --exclude='package.json' \
  --exclude='.realm.json' \
  --exclude='.gitignore' \
  --exclude='tests/' \
  --exclude='*-test.gts' \
  "$CATALOG_SRC/" "$CATALOG_REALM/"

echo "[copy-catalog] Done."
