#!/usr/bin/env python3
"""The pre-review checklist for a Spec promotion PR.

  python3 scripts/check-promotion.py                 # check the whole catalog
  python3 scripts/check-promotion.py cards/hr        # check one folder
  python3 scripts/check-promotion.py --changed main  # check what this PR touches
  python3 scripts/check-promotion.py --json          # machine output

CI owns the mechanical checks so a human reviewer starts from a clean PR and
spends their judgment on prose, shape and naming instead. Each check encodes a
defect that a reviewer would otherwise have to catch by hand:

  spec-ref          a Spec whose ref does not resolve verifies nothing
  spec-name         no cardInfo.name -> the crawl cannot repoint the tracker
                    row, so promoting the code silently un-verifies the concept
  spec-title        cardTitle convention: bare name, fields get " Field"
  spec-description  the Spec chooser tile renders blank without it
  spec-readme-floor >= 300 chars (convention)
  spec-readme       the import line names the catalog module (error)
  spec-coverage     every moved module has a Spec: the catalog holds no loose code
  example-link      a linked example that 404s renders an empty Examples section
  instance-adopts   instance adoptsFrom must be RELATIVE: an absolute
                    @cardstack/catalog ref to a not-yet-merged module makes the
                    submissions push fail with a 500
  import-base       base imports use the canonical @cardstack/base/ alias
  import-dangling   every relative import resolves on disk
  import-matrix     nothing still imports the matrix realm
  import-inverted   shared code (fields/, components/, commands/) never imports
                    a domain card out of cards/

Findings carry a severity. ERROR is always wrong and always fails. CONVENTION
is what ARRIVING content owes: it fails for a file the PR adds, and is
reported without failing for anything else, so a PR is judged on what it
brings rather than on the backlog it happens to touch.

Two rules are deliberately narrow, because the wide reading of each flags
correct code:

  A field importing a shared component is NOT an upward dependency -- status,
  priority and due-date all render through components/state-pill by design.
  Only a reach into cards/ inverts the layering.

  An absolute @cardstack/catalog adoptsFrom is only fatal when it names a
  module the same PR adds: the submissions push 500s on a module that is not
  merged. Pointing at an already-merged module, the way every FieldListing
  instance points at catalog-app/listing/listing, is correct.

Exit 0 when every check passes, 1 when any fails. Reads only.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Any author's realm on the staging host, not one person's.
MATRIX_REALM_RE = re.compile(r"realms-staging\.stack\.cards/[^/'\"]+/boxel-software-matrix-layer")
BASE_OK = "@cardstack/base/"
BASE_DRIFT = "https://cardstack.com/base/"
CODE_EXT = (".gts", ".ts")
SHARED_DIRS = ("fields", "components", "commands", "utils")
BLOCK_DIRS = SHARED_DIRS + ("cards",)
# Folders that document a block rather than being one: their modules need no
# Spec of their own and may consume anything they like to render an example.
DOC_SEGMENTS = ("/example/", "/Spec/")

ERROR = "error"
CONVENTION = "convention"

# A multi-line import puts its specifier on a line starting with a brace, so
# the `from` clause is matched wherever it lands rather than anchored on the
# import keyword.
IMPORT_RE = re.compile(
    r"""\bfrom\s*['"]([^'"]+)['"]"""
    r"""|^\s*import\s*['"]([^'"]+)['"]""", re.M)
# The readMe's consumption line: a fenced import naming the module.
README_IMPORT_RE = re.compile(r"""from\s*['"]([^'"]+)['"]""")


class Report:
    def __init__(self):
        self.findings = []

    def fail(self, check, path, detail, severity=ERROR):
        self.findings.append({"check": check, "path": path, "detail": detail,
                              "severity": severity})

    def blocking(self, strict):
        return [f for f in self.findings
                if strict or f["severity"] == ERROR]


# ---------------------------------------------------------------- helpers

def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def resolve_module(from_dir, spec):
    """Resolve a relative module specifier to a repo-relative file, or None."""
    base = os.path.normpath(os.path.join(from_dir, spec))
    # The specifier as written comes first: a realm module may carry its own
    # extension, and a readMe's consumption line usually does.
    for cand in (base, base + ".gts", base + ".ts",
                 os.path.join(base, "index.gts"), os.path.join(base, "index.ts")):
        if os.path.isfile(cand):
            return rel(cand)
    return None


def is_doc_module(path):
    """An example or a Spec's own renderer documents a block; it is not one."""
    return any(seg in "/" + path for seg in DOC_SEGMENTS)


def scope_paths(args):
    """The files this run judges."""
    if args.changed:
        merge_base = subprocess.run(
            ["git", "merge-base", args.changed, "HEAD"],
            cwd=ROOT, capture_output=True, text=True).stdout.strip()
        out = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=ACMR",
             merge_base or args.changed, "HEAD"],
            cwd=ROOT, capture_output=True, text=True).stdout.split()
        # A promotion is ALL new files, so against an uncommitted branch git
        # diff reports nothing and the run would pass having looked at nothing.
        # Untracked files cover that, but ONLY when the branch has no commits:
        # sweeping them in otherwise drags in whatever local scratch the working
        # copy holds, and a check that fails on an unrelated spike folder is a
        # check people learn to ignore.
        if not out:
            out = subprocess.run(
                ["git", "ls-files", "--others", "--exclude-standard"],
                cwd=ROOT, capture_output=True, text=True).stdout.split()
            if out:
                print("  (nothing committed on this branch yet — checking "
                      f"{len(out)} untracked files instead)")
        return sorted({p for p in out
                       if os.path.isfile(os.path.join(ROOT, p))})
    roots = args.paths or ["."]
    out = []
    for r in roots:
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, r)):
            dirnames[:] = [d for d in dirnames
                           if not d.startswith(".") and d != "node_modules"]
            for name in filenames:
                out.append(rel(os.path.join(dirpath, name)))
    return out


def load_json(path):
    try:
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


def is_spec(doc):
    """A Spec, including the catalog's own subclasses.

    Ten shared fields adopt a per-field subclass (StatusFieldSpec,
    RatingFieldSpec, …) rather than Spec itself. Matching only "Spec" skips
    every check on those files AND makes the coverage check report their
    modules as unspecced."""
    data = doc.get("data") or {}
    adopts = (data.get("meta") or {}).get("adoptsFrom") or {}
    name = adopts.get("name") or ""
    if name == "Spec" or name.endswith("Spec"):
        return True
    attrs = data.get("attributes") or {}
    return bool(attrs.get("specType")) and isinstance(attrs.get("ref"), dict)


# ---------------------------------------------------------------- checks

TEMPLATE_LITERAL_RE = re.compile(r"`(?:\\.|[^`\\])*`", re.S)
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)


def strip_noncode(src):
    """Blank out template literals and block comments before scanning imports.

    A fixture that stores card source in backticks otherwise reports its
    embedded import paths as dangling."""
    src = BLOCK_COMMENT_RE.sub("", src)
    return TEMPLATE_LITERAL_RE.sub("``", src)


def check_code(paths, report):
    for path in paths:
        if not path.endswith(CODE_EXT):
            continue
        try:
            src = open(os.path.join(ROOT, path), encoding="utf-8",
                       errors="ignore").read()
        except OSError:
            continue
        from_dir = os.path.dirname(os.path.join(ROOT, path))
        top = path.split("/", 1)[0]
        for m in IMPORT_RE.finditer(strip_noncode(src)):
            spec = m.group(1) or m.group(2)
            if not spec:
                continue
            if spec.startswith(BASE_DRIFT):
                report.fail("import-base", path,
                            f"{spec} — base imports use the canonical "
                            f"{BASE_OK}… alias", CONVENTION)
                continue
            if MATRIX_REALM_RE.search(spec):
                report.fail("import-matrix", path,
                            f"{spec} — still points at the matrix realm")
                continue
            if spec.startswith("."):
                target = resolve_module(from_dir, spec)
                if not target:
                    report.fail("import-dangling", path,
                                f"{spec} does not resolve on disk")
                    continue
                if (top in SHARED_DIRS and target.startswith("cards/")
                        and not is_doc_module(path)):
                    report.fail("import-inverted", path,
                                f"imports {target} — shared {top}/ code must "
                                f"not depend on a domain card")


def check_specs(paths, report, added=None):
    """Returns module -> spec path, so coverage can be judged after."""
    covered = {}
    for path in paths:
        if not path.endswith(".json"):
            continue
        doc = load_json(path)
        if not doc or not is_spec(doc):
            continue
        attrs = (doc.get("data") or {}).get("attributes") or {}
        # Conventions are what ARRIVING content owes. Judging every Spec a PR
        # happens to touch would block routine traffic on a backlog the PR did
        # not create: most Specs already in the catalog carry no cardInfo.name
        # and no cardDescription.
        arriving = added is None or path in added
        spec_dir = os.path.dirname(os.path.join(ROOT, path))
        name = ((attrs.get("cardInfo") or {}).get("name") or "").strip()
        spec_type = (attrs.get("specType") or "").strip()
        title = (attrs.get("cardTitle") or "").strip()
        desc = (attrs.get("cardDescription") or "").strip()
        readme = attrs.get("readMe") or ""

        ref = attrs.get("ref") or {}
        module = (ref.get("module") or "").strip()
        target = None
        if module.startswith("."):
            target = resolve_module(spec_dir, module)
            if not target:
                report.fail("spec-ref", path,
                            f"ref.module {module} does not resolve")
            else:
                covered[target] = path
        elif not module:
            report.fail("spec-ref", path, "ref has no module")

        if arriving:
            if not name:
                report.fail("spec-name", path,
                            "cardInfo.name is empty — the crawl matches tracker "
                            "rows on this field, so the row keeps pointing at "
                            "the realm Spec and the close-out un-verifies it",
                            CONVENTION)
            if not title:
                report.fail("spec-title", path, "cardTitle is empty", CONVENTION)
            elif spec_type == "field" and not title.endswith(" Field"):
                report.fail("spec-title", path,
                            f'cardTitle "{title}" — a field Spec\'s title ends '
                            f'in " Field"', CONVENTION)
            elif spec_type != "field" and title.endswith(" Field"):
                report.fail("spec-title", path,
                            f'cardTitle "{title}" — only field Specs carry the '
                            f'" Field" suffix', CONVENTION)
            if not desc:
                report.fail("spec-description", path,
                            "cardDescription is empty — the Spec chooser tile "
                            "renders blank", CONVENTION)
            if len(readme) < 300:
                report.fail("spec-readme-floor", path,
                            f"readMe is {len(readme)} chars, below the 300-char "
                            f"floor", CONVENTION)
        for imported in README_IMPORT_RE.findall(readme):
            if MATRIX_REALM_RE.search(imported):
                report.fail("spec-readme", path,
                            f"readMe imports {imported} — the consumption line "
                            f"names the realm the code came from, not where it "
                            f"lives now")
            elif arriving and imported.startswith(BASE_DRIFT):
                report.fail("import-base", path,
                            f"readMe imports {imported} — base imports use the "
                            f"canonical {BASE_OK}… alias", CONVENTION)
            elif imported.startswith(".") and not resolve_module(spec_dir, imported):
                report.fail("spec-readme", path,
                            f"readMe imports {imported}, which does not resolve "
                            f"from the Spec folder")

        rels = (doc.get("data") or {}).get("relationships") or {}
        for key in sorted(k for k in rels if k.startswith("linkedExamples.")):
            link = ((rels[key] or {}).get("links") or {}).get("self")
            if not link:
                continue
            if link.startswith("."):
                resolved = os.path.normpath(os.path.join(spec_dir, link)) + ".json"
                if not os.path.isfile(resolved):
                    report.fail("example-link", path,
                                f"{key} -> {link} does not resolve")
            elif MATRIX_REALM_RE.search(link):
                report.fail("example-link", path,
                            f"{key} -> {link} still points at the matrix realm")
    return covered


def added_by_pr(base):
    """Paths this branch adds relative to BASE.

    Falls back to untracked files the same way `scope_paths` does. Without that
    fallback, a branch with nothing committed yields an empty set, and then the
    coverage check skips every path while the absolute-adoptsFrom check can
    fire neither severity — two checks reporting clean having looked at
    nothing, in the one mode the untracked fallback exists to cover."""
    if not base:
        return None
    merge_base = subprocess.run(["git", "merge-base", base, "HEAD"], cwd=ROOT,
                                capture_output=True, text=True).stdout.strip()
    out = subprocess.run(["git", "diff", "--name-only", "--diff-filter=A",
                          merge_base or base, "HEAD"],
                         cwd=ROOT, capture_output=True, text=True).stdout.split()
    if not out:
        out = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"],
                             cwd=ROOT, capture_output=True, text=True).stdout.split()
    return set(out)


def check_instances(paths, report, added=None):
    for path in paths:
        if not path.endswith(".json"):
            continue
        doc = load_json(path)
        if not doc:
            continue
        data = doc.get("data") or {}
        adopts = (data.get("meta") or {}).get("adoptsFrom") or {}
        module = (adopts.get("module") or "").strip()
        if not module or is_spec(doc):
            continue
        if module.startswith("@cardstack/catalog/"):
            target = module[len("@cardstack/catalog/"):]
            unmerged = added is not None and any(
                f"{target}{ext}" in added for ext in (".gts", ".ts"))
            if unmerged:
                report.fail("instance-adopts", path,
                            f"adoptsFrom {module} is absolute and names a "
                            f"module this PR adds — the submissions push "
                            f"fails with a 500; use a relative path")
            elif added is None:
                report.fail("instance-adopts", path,
                            f"adoptsFrom {module} is absolute; safe only "
                            f"because the module is already merged",
                            CONVENTION)
        elif MATRIX_REALM_RE.search(module):
            report.fail("instance-adopts", path,
                        f"adoptsFrom {module} still points at the matrix realm")
        elif module.startswith("."):
            if not resolve_module(os.path.dirname(os.path.join(ROOT, path)), module):
                report.fail("instance-adopts", path,
                            f"adoptsFrom {module} does not resolve on disk")


def check_coverage(paths, covered, report, added=None):
    """Every module the PR ADDS carries a Spec — the catalog holds no loose
    code, thin Specs included.

    Only added modules. `covered` is built from the Specs in this run's scope,
    so a PR that merely edits an existing module would otherwise be told its
    module has no Spec, when the Spec simply sits outside the diff."""
    for path in paths:
        if added is not None and path not in added:
            continue
        if not path.endswith(CODE_EXT):
            continue
        if path in covered:
            continue
        top = path.split("/", 1)[0]
        if top not in BLOCK_DIRS:
            continue
        base = os.path.basename(path)
        if base.endswith((".test.gts", ".test.ts")) or base == "utils.ts":
            continue
        if is_doc_module(path):
            continue
        report.fail("spec-coverage", path,
                    "no Spec points at this module — a consumer cannot find it",
                    CONVENTION)


# ---------------------------------------------------------------- output

def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", help="folders to check (default: all)")
    ap.add_argument("--changed", metavar="BASE",
                    help="only files this branch changed against BASE")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    paths = scope_paths(args)
    # A promotion PR owes the conventions; a whole-tree audit only reports them.
    strict = bool(args.changed)
    report = Report()
    added = added_by_pr(args.changed)
    check_code(paths, report)
    covered = check_specs(paths, report, added)
    check_instances(paths, report, added)
    check_coverage(paths, covered, report, added)
    blocking = report.blocking(strict)

    if args.json:
        print(json.dumps({"ok": not blocking, "strict": strict,
                          "checked": len(paths), "blocking": len(blocking),
                          "findings": report.findings}, indent=2))
        return 0 if not blocking else 1

    by_check = defaultdict(list)
    for f in report.findings:
        by_check[f["check"]].append(f)

    mode = f"promotion PR vs {args.changed}" if strict else "audit"
    print(f"\nPROMOTION CHECK — {len(paths)} files, {mode}")
    if strict:
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"],
                               cwd=ROOT, capture_output=True, text=True).stdout.split("\n")
        dirty = [l[3:] for l in dirty if l.strip()]
        if dirty:
            print(f"  ({len(dirty)} uncommitted change(s) NOT checked — the diff "
                  f"reads commits: {', '.join(dirty[:3])}"
                  f"{'…' if len(dirty) > 3 else ''})")
    if strict and not paths:
        print("\n  nothing to check — is this branch actually ahead of "
              f"{args.changed}?\n")
        return 1
    if not report.findings:
        print("\n  all checks pass\n")
        return 0

    errors = sum(1 for f in report.findings if f["severity"] == ERROR)
    conventions = len(report.findings) - errors
    print(f"\n  {errors} errors, {conventions} convention findings"
          f"{'' if strict else ' (reported, not blocking)'}\n")
    def rank(check):
        return (all(f["severity"] != ERROR for f in by_check[check]), check)

    for check in sorted(by_check, key=rank):
        items = by_check[check]
        errs = sum(1 for f in items if f["severity"] == ERROR)
        tag = ("ERROR" if errs == len(items)
               else "convention" if errs == 0
               else f"{errs} ERROR + {len(items) - errs} convention")
        print(f"  [{tag}] {check} ({len(items)})")
        for f in items[:12]:
            mark = "" if errs in (0, len(items)) else (
                "ERROR " if f["severity"] == ERROR else "convention ")
            print(f"    {mark}{f['path']}")
            print(f"      {f['detail']}")
        if len(items) > 12:
            print(f"    … {len(items) - 12} more")
        print()
    if blocking:
        return 1
    print("  nothing blocking\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
