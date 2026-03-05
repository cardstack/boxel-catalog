#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BOXEL_CATALOG_REALM="${BOXEL_CATALOG_REALM:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Check that files in boxel-catalog are in sync with packages/catalog-realm.
Only files that already exist in boxel-catalog are compared. New files in
packages/catalog-realm that don't exist here are ignored.

Options:
  --source PATH    Path to packages/catalog-realm (or set \$BOXEL_CATALOG_REALM)
  -h, --help       Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      BOXEL_CATALOG_REALM="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$BOXEL_CATALOG_REALM" ]]; then
  echo "Error: Source directory not specified."
  echo "Set BOXEL_CATALOG_REALM env var or use --source to specify the path to packages/catalog-realm."
  exit 1
fi

if [[ ! -d "$BOXEL_CATALOG_REALM" ]]; then
  echo "Error: Source directory not found: $BOXEL_CATALOG_REALM"
  exit 1
fi

echo "Checking boxel-catalog files against: $BOXEL_CATALOG_REALM/"
echo ""

# Dirs/files that are unique to boxel-catalog (not in catalog-realm)
EXCLUDES=(
  ".git"
  ".github"
  ".gitignore"
  ".boxel"
  ".claude"
  ".realm.json"
  "LICENSE"
  "README.md"
  "scripts"
  "tests"
  "node_modules"
  "index.json"
)

# Build find exclude args
FIND_EXCLUDES=()
for excl in "${EXCLUDES[@]}"; do
  FIND_EXCLUDES+=(-path "./$excl" -prune -o)
done

DIFF_COUNT=0
DIFF_FILES=()

cd "$CATALOG_DIR"
while IFS= read -r file; do
  source_file="$BOXEL_CATALOG_REALM/$file"
  if [[ -f "$source_file" ]]; then
    if ! diff -q "$file" "$source_file" > /dev/null 2>&1; then
      DIFF_FILES+=("$file")
      ((DIFF_COUNT++))
    fi
  fi
done < <(find . "${FIND_EXCLUDES[@]}" -type f -print | sed 's|^\./||')

# Check for new files in catalog-realm inside folders that already exist in boxel-catalog
NEW_COUNT=0
NEW_FILES=()

# Get top-level dirs in boxel-catalog (tracked by git, excluding repo-specific ones)
TRACKED_DIRS=()
while IFS= read -r dir; do
  skip=false
  for excl in "${EXCLUDES[@]}"; do
    if [[ "$dir" == "$excl" ]]; then
      skip=true
      break
    fi
  done
  if [[ "$skip" == false && -d "$CATALOG_DIR/$dir" && -d "$BOXEL_CATALOG_REALM/$dir" ]]; then
    TRACKED_DIRS+=("$dir")
  fi
done < <(git -C "$CATALOG_DIR" ls-files | sed 's|/.*||' | sort -u)

for dir in "${TRACKED_DIRS[@]}"; do
  while IFS= read -r source_file; do
    rel_path="${source_file#$BOXEL_CATALOG_REALM/}"
    if [[ ! -e "$CATALOG_DIR/$rel_path" ]]; then
      NEW_FILES+=("$rel_path")
      ((NEW_COUNT++))
    fi
  done < <(find "$BOXEL_CATALOG_REALM/$dir" -type f)
done

HAS_ERRORS=false

if [[ $DIFF_COUNT -gt 0 ]]; then
  echo "Found $DIFF_COUNT file(s) out of sync:"
  echo ""
  for f in "${DIFF_FILES[@]}"; do
    echo "  $f"
  done
  echo ""
  HAS_ERRORS=true
fi

if [[ $NEW_COUNT -gt 0 ]]; then
  echo "Found $NEW_COUNT new file(s) in packages/catalog-realm in tracked folders:"
  echo ""
  for f in "${NEW_FILES[@]}"; do
    echo "  $f"
  done
  echo ""
  HAS_ERRORS=true
fi

if [[ "$HAS_ERRORS" == true ]]; then
  echo "boxel-catalog is out of sync with packages/catalog-realm."
  exit 1
else
  echo "All existing files are in sync. No new files in tracked folders."
  exit 0
fi
