#!/usr/bin/env python3
"""Lane A4 support — what a promotion PR changed BEYOND moving the code.

  python3 scripts/promotion-residue.py cards/hr

The pilot's rule is that modules move verbatim apart from import rewriting.
Everything else in the diff is a deliberate change and is where regressions
enter, because those edits are written under type-checker pressure rather than
design pressure. A reviewer needs exactly those lines and nothing else.

A plain diff cannot give them. Hoisting `static isolated = class {…}` into a
top-level class re-indents and relocates hundreds of lines per card, and even
ignoring whitespace a moved block reads as a delete plus an insert, so the diff
runs to thousands of lines that changed nothing.

So this compares line MULTISETS per module, ignoring import lines, whitespace
and brace-only lines. A pure move cancels out, leaving only lines genuinely
added or removed -- a scale a reviewer can actually read.

Pairs a catalog module with its matrix-realm original by basename WITH the
extension: dropping the extension pairs utils/sort.ts with components/sort.gts,
which are unrelated blocks."""
import collections, os, re, sys
CAT=os.path.expanduser("~/Developer/boxel-catalog")
MIR=os.path.expanduser("~/Developer/boxel/packages/experiments-realm/boxel-software-matrix-layer")
FOLDER=sys.argv[1] if len(sys.argv)>1 else "cards/hr"
# Drops whole import statements, multi-line ones included: the specifier line of
# a multi-line import starts with `}`, so anchoring on the import keyword left
# `} from '...';` in the comparison and reported pure import rewrites as content.
IMP=re.compile(r"""^\s*(?:import|export)\b.*?from\s*['"][^'"]+['"];?\s*$"""
               r"""|^\s*import\s*['"][^'"]+['"];?\s*$"""
               r"""|^\s*\}?\s*from\s*['"][^'"]+['"];?\s*$"""
               r"""|^\s*(?:import|export)\s*\{\s*$"""
               r"""|^\s*(?:type\s+)?[A-Za-z_$][\w$]*\s*,\s*$""")
TRIVIAL={"","{","}","});","}","}}","},",")","(",");","};","]","[","},{"}

def bag(path):
    c=collections.Counter()
    for line in open(path,encoding="utf-8",errors="ignore"):
        if IMP.match(line.rstrip("\n")): continue
        n=re.sub(r"\s+"," ",line).strip()
        if n in TRIVIAL: continue
        c[n]+=1
    return c

mirror_index={}
for dp,dn,fn in os.walk(MIR):
    dn[:]=[d for d in dn if not d.startswith(".")]
    for n in fn:
        if n.endswith((".gts",".ts")): mirror_index.setdefault(n,os.path.join(dp,n))

root=os.path.join(CAT,FOLDER)
rows=[]
for dp,dn,fn in os.walk(root):
    dn[:]=[d for d in dn if not d.startswith(".")]
    for n in fn:
        if not n.endswith((".gts",".ts")) or n.endswith((".test.gts",".test.ts")): continue
        rel=os.path.relpath(os.path.join(dp,n),root)
        if rel.startswith(("Spec"+os.sep,"example"+os.sep)): continue
        hit=mirror_index.get(n)
        if not hit: rows.append((rel,None,None)); continue
        a,b=bag(hit),bag(os.path.join(dp,n))
        rows.append((rel,(a-b),(b-a)))

tot_rm=tot_add=0
for rel,removed,added in sorted(rows):
    if removed is None:
        print(f"\n### {rel} — NEW on arrival"); continue
    if not removed and not added: continue
    tot_rm+=sum(removed.values()); tot_add+=sum(added.values())
    print(f"\n### {rel}  -{sum(removed.values())} +{sum(added.values())}")
    for l,c in list(removed.items())[:25]: print(f"   - {l[:150]}")
    for l,c in list(added.items())[:25]: print(f"   + {l[:150]}")
    if len(removed)>25 or len(added)>25: print("   … truncated")
print(f"\n==== real content change: -{tot_rm} +{tot_add} lines")
