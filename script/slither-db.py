#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# slither-db.py
#
# Normalizes the Slither triage database (slither.db.json). `slither --triage-mode`
# appends each accepted result as a full JSON object on one line, including
# `elements[].source_mapping.filename_absolute` (a local home-directory path), and
# records no reason. Slither matches triaged results by `id` alone, so this keeps
# only check, impact, id, description and reason, sorts the entries, and writes the
# file with two-space indentation. It fails while any entry has an empty `reason`;
# an entry that had none gets `"reason": ""` to fill in.
#
# Usage: script/slither-db.py [--check] [path]   (path defaults to slither.db.json)
#   (no flag)  rewrite the file in place (`make slither-triage` runs this)
#   --check    rewrite nothing; fail when the file is not already normalized (CI)
# ---------------------------------------------------------------------------
import json
import sys

KEYS = ("check", "impact", "id", "description", "reason")


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    path = args[0] if args else "slither.db.json"
    with open(path, encoding="utf-8") as f:
        text = f.read()

    entries, seen = [], set()
    for raw in json.loads(text):
        if raw["id"] in seen:
            continue
        seen.add(raw["id"])
        entry = {k: raw.get(k, "") for k in KEYS}
        entry["reason"] = entry["reason"].strip()
        entries.append(entry)
    entries.sort(key=lambda e: (e["check"], e["description"], e["id"]))
    normalized = json.dumps(entries, indent=2, ensure_ascii=False) + "\n"

    ok = True
    for e in entries:
        if not e["reason"]:
            ok = False
            print(f"{path}: {e['check']} {e['id'][:12]} has no reason: {e['description'].splitlines()[0]}")
    if check:
        if text != normalized:
            ok = False
            print(f"{path} is not normalized: run script/slither-db.py (make slither-triage runs it).")
    elif text != normalized:
        with open(path, "w", encoding="utf-8") as f:
            f.write(normalized)
    if not ok:
        print("Give each triaged result a one-line `reason` saying why it is a false positive.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
