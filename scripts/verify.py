#!/usr/bin/env python3
"""AegisRP structural verifier.

No standalone Lua 5.0 interpreter is assumed, so this catches the two failure
classes that brick a 1.12 addon before it ever loads:

  1. Structural imbalance - unmatched ( ) { } or a function/if/for/while count
     that doesn't equal the `end` count (after stripping comments + strings).
  2. Lua 5.1-isms that do not exist in the 1.12 client's Lua 5.0:
       - the `#` length operator          (use table.getn)
       - string.gmatch                    (use string.gfind)
       - select(...)                      (use table.getn / arg)
       - the numeric `%` modulo operator  (use math.mod)

Run after EVERY edit:
    python3 scripts/verify.py                # checks Core/ + Classes/
    python3 scripts/verify.py path/to.lua    # or specific files

Exit code 0 = all clean; 1 = problems found. In-game testing is still the real
test - runtime errors print to chat.
"""
import re
import sys
import glob
import os

def strip_lua(src: str) -> str:
    """Remove -- line comments and quoted strings (naive but sufficient:
    this codebase avoids long strings/comments)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src[i:i+2] == "--":
            j = src.find("\n", i)
            i = j if j != -1 else n
            continue
        c = src[i]
        if c in "\"'":
            q = c
            i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)

def check(path: str) -> bool:
    src = open(path, encoding="utf-8", errors="replace").read()
    t = strip_lua(src)
    problems = []

    pairs = [("(", ")"), ("{", "}"), ("[", "]")]
    for a, b in pairs:
        if t.count(a) != t.count(b):
            problems.append(f"{a}{b} imbalance: {t.count(a)} vs {t.count(b)}")

    openers = len(re.findall(r"\bfunction\b|\bif\b|\bfor\b|\bwhile\b", t))
    enders = len(re.findall(r"\bend\b", t))
    # `repeat ... until` doesn't use `end`; this codebase doesn't use repeat.
    if openers != enders:
        problems.append(f"block imbalance: {openers} openers vs {enders} end")

    if re.search(r"#\w", t):
        problems.append("Lua 5.1-ism: '#' length operator (use table.getn)")
    if "gmatch" in t:
        problems.append("Lua 5.1-ism: string.gmatch (use string.gfind)")
    if re.search(r"\bselect\s*\(", t):
        problems.append("Lua 5.1-ism: select() (not in Lua 5.0)")
    if re.search(r"[%w%)]\s*%%\s*[%w%(]".replace("%w", r"\w").replace("%)", r"\)").replace("%(", r"\("), t):
        problems.append("Lua 5.1-ism: numeric % operator (use math.mod)")

    name = os.path.relpath(path)
    if problems:
        print(f"FAIL  {name}")
        for p in problems:
            print(f"      - {p}")
        return False
    print(f"OK    {name}  ()={t.count('(')} blocks={openers}")
    return True

def main():
    args = sys.argv[1:]
    if args:
        files = args
    else:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        files = sorted(glob.glob(os.path.join(root, "Core", "*.lua"))) + \
                sorted(glob.glob(os.path.join(root, "Classes", "*.lua")))
    ok = True
    for f in files:
        ok = check(f) and ok
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
