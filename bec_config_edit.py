#!/usr/bin/env python3
"""Console editor for BEC .conf files; values remain Lua literals."""
import json
import os
import sys


EDITABLE = {
    "automation.storageAddress",
    "automation.gateAddress",
    "automation.cacheInterfaceAddress",
    "automation.cacheInterfaceType",
    "automation.buffers",
    "automation.redstone",
    "automation.nanite",
    "automation.refill",
    "routeMapper.referenceInterfaceAddress",
    "routeMapper.redstoneAddresses",
    "routeMapper.testSides",
}


def _is_number(value: str) -> bool:
    try:
        float(value)
        return True
    except ValueError:
        return False


def literal(value: str) -> str:
    if value == "!clear":
        return '""'
    stripped = value.strip()
    if (stripped.startswith(("{", "\"", "'")) or stripped in {"true", "false", "nil"}
            or _is_number(stripped)):
        return value
    return json.dumps(value, ensure_ascii=False)


def load(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()
    entries = []
    for index, line in enumerate(lines):
        fields = line.rstrip("\r\n").split("\t", 2)
        if (len(fields) == 3 and not fields[0].lstrip().startswith("#")
                and fields[0] in EDITABLE):
            entries.append((index, fields[0], fields[1], fields[2]))
    return lines, entries


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "bec.conf"
    lines, entries = load(path)
    if not entries:
        raise SystemExit("no editable entries found")
    print("Choose entry numbers or names separated by commas; 'all' edits every entry.")
    for number, (_, name, label, value) in enumerate(entries, 1):
        print(f"{number:3d}. {name} | {label} | {value}")
    selection = input("entries (blank exits): ").strip()
    if not selection:
        return
    if selection.lower() == "all":
        selected = list(range(len(entries)))
    else:
        by_name = {entry[1]: index for index, entry in enumerate(entries)}
        selected = []
        for token in selection.split(","):
            token = token.strip()
            if token.isdigit() and 1 <= int(token) <= len(entries):
                selected.append(int(token) - 1)
            elif token in by_name:
                selected.append(by_name[token])
            else:
                print(f"unknown entry: {token}")
        selected = list(dict.fromkeys(selected))
    for selected_index in selected:
        line_index, name, label, old = entries[selected_index]
        value = input(f"{name} | {label} | {old}\nnew value (blank keeps, !clear empties): ")
        if value != "": lines[line_index] = f"{name}\t{label}\t{literal(value)}\n"
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8", newline="") as handle:
        handle.writelines(lines)
    os.replace(temporary, path)
    print(f"configuration updated: {path}")


if __name__ == "__main__":
    main()
