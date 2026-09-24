#!/usr/bin/env python3
"""Field-by-field console editor for BEC .conf files."""
import json
import os
import re
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

FIELD_LABELS = {
    "automation.buffers": {
        "itemInterfaceAddress": "物品缓存接口地址",
        "fluidInterfaceAddress": "流体缓存接口地址",
        "interfaceType": "接口类型",
    },
    "automation.redstone": {
        "nodeAddress": "节点输出红石地址",
        "generatorAddress": "生成器输出红石地址",
        "synthesisAddress": "合成控制红石地址",
        "haltAddress": "停止控制红石地址",
        "nodeToggleSide": "节点输出方向",
        "generatorToggleSide": "生成器输出方向",
        "synthesisSide": "合成控制方向",
        "haltSide": "停止控制方向",
    },
    "automation.nanite": {
        "storageBusAddress": "存储总线地址",
        "inputSide": "存储总线输入方向",
        "ejectRedstoneAddress": "回收红石地址",
        "ejectSide": "回收红石方向",
        "transposerAddress": "转运器地址",
        "targetSide": "转运器目标方向",
        "targetOutputSlot": "转运器目标槽位",
    },
    "automation.refill": {
        "routeModule": "路由模块",
        "cacheInterfaceAddress": "补货缓存接口地址",
        "cacheInterfaceType": "补货缓存接口类型",
        "entanglerAddress": "纠缠装置控制红石地址",
        "entanglerToggleSide": "纠缠装置控制方向",
        "activityAddress": "活动信号地址",
        "activitySide": "活动信号方向",
    },
}

FIELD_ORDER = {
    "automation.buffers": [
        "itemInterfaceAddress", "fluidInterfaceAddress", "interfaceType",
    ],
    "automation.redstone": [
        "nodeAddress", "generatorAddress", "synthesisAddress", "haltAddress",
        "nodeToggleSide", "generatorToggleSide", "synthesisSide", "haltSide",
    ],
    "automation.nanite": [
        "storageBusAddress", "inputSide", "ejectRedstoneAddress", "ejectSide",
        "transposerAddress", "targetSide", "targetOutputSlot",
    ],
    "automation.refill": [
        "routeModule", "cacheInterfaceAddress", "cacheInterfaceType",
        "entanglerAddress", "entanglerToggleSide", "activityAddress", "activitySide",
    ],
}


class LuaLiteralParser:
    """Parse the literal subset used by BEC configuration values."""

    _number = re.compile(r"[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?")
    _identifier = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

    def __init__(self, text):
        self.text = text
        self.index = 0

    def error(self, message):
        raise ValueError(f"{message} at column {self.index + 1}")

    def skip(self):
        while self.index < len(self.text) and self.text[self.index].isspace():
            self.index += 1

    def parse(self):
        value = self.parse_value()
        self.skip()
        if self.index != len(self.text):
            self.error("unexpected text")
        return value

    def parse_value(self):
        self.skip()
        if self.index >= len(self.text):
            self.error("expected a value")
        char = self.text[self.index]
        if char == "{":
            return self.parse_table()
        if char in "\"'":
            return self.parse_string()
        for keyword, value in (("true", True), ("false", False), ("nil", None)):
            end = self.index + len(keyword)
            if self.text.startswith(keyword, self.index) and (
                    end == len(self.text) or not (self.text[end].isalnum() or self.text[end] == "_")):
                self.index = end
                return value
        match = self._number.match(self.text, self.index)
        if match:
            self.index = match.end()
            token = match.group(0)
            return float(token) if any(char in token for char in ".eE") else int(token)
        self.error("expected a literal")

    def parse_string(self):
        quote = self.text[self.index]
        self.index += 1
        result = []
        escapes = {
            "a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r",
            "t": "\t", "v": "\v", "\\": "\\", "\"": "\"", "'": "'",
        }
        while self.index < len(self.text):
            char = self.text[self.index]
            self.index += 1
            if char == quote:
                return "".join(result)
            if char != "\\":
                result.append(char)
                continue
            if self.index >= len(self.text):
                self.error("unterminated escape")
            escaped = self.text[self.index]
            self.index += 1
            if escaped == "x" and self.index + 2 <= len(self.text):
                digits = self.text[self.index:self.index + 2]
                if re.fullmatch(r"[0-9A-Fa-f]{2}", digits):
                    result.append(chr(int(digits, 16)))
                    self.index += 2
                    continue
            result.append(escapes.get(escaped, escaped))
        self.error("unterminated string")

    def parse_table(self):
        self.index += 1
        result = {}
        array_index = 1
        while True:
            self.skip()
            if self.index >= len(self.text):
                self.error("unterminated table")
            if self.text[self.index] == "}":
                self.index += 1
                return result
            if self.text[self.index] == "[":
                self.index += 1
                key = self.parse_value()
                self.skip()
                if self.index >= len(self.text) or self.text[self.index] != "]":
                    self.error("expected ]")
                self.index += 1
                self.skip()
                if self.index >= len(self.text) or self.text[self.index] != "=":
                    self.error("expected =")
                self.index += 1
                value = self.parse_value()
            else:
                identifier = self._identifier.match(self.text, self.index)
                if identifier:
                    lookahead = identifier.end()
                    while lookahead < len(self.text) and self.text[lookahead].isspace():
                        lookahead += 1
                    if lookahead < len(self.text) and self.text[lookahead] == "=":
                        key = identifier.group(0)
                        self.index = lookahead + 1
                        value = self.parse_value()
                    else:
                        key = array_index
                        array_index += 1
                        value = self.parse_value()
                else:
                    key = array_index
                    array_index += 1
                    value = self.parse_value()
            result[key] = value
            self.skip()
            if self.index < len(self.text) and self.text[self.index] == ",":
                self.index += 1
                continue
            if self.index < len(self.text) and self.text[self.index] == "}":
                self.index += 1
                return result
            self.error("expected comma or }")


def parse_lua_literal(text):
    return LuaLiteralParser(text).parse()


def serialize(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if not isinstance(value, dict):
        raise ValueError(f"cannot serialize {type(value).__name__}")

    def key_order(key):
        if isinstance(key, (int, float)) and not isinstance(key, bool):
            return 0, key
        return 1, str(key)

    parts = []
    for key in sorted(value, key=key_order):
        if isinstance(key, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            prefix = f"{key} = "
        else:
            prefix = f"[{serialize(key)}] = "
        parts.append(prefix + serialize(value[key]))
    return "{ " + ", ".join(parts) + " }"


def literal_text(value):
    if value == "!clear":
        return '""'
    stripped = value.strip()
    if (stripped.startswith(("{", '"', "'")) or stripped in {"true", "false", "nil"}
            or re.fullmatch(r"[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?", stripped)):
        return stripped
    return json.dumps(value, ensure_ascii=False)


def load(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.readlines()
    entries = []
    for index, line in enumerate(lines):
        fields = line.rstrip("\r\n").split("\t", 2)
        if (len(fields) == 3 and not fields[0].lstrip().startswith("#")
                and fields[0] in EDITABLE):
            entries.append({"index": index, "name": fields[0], "label": fields[1], "raw": fields[2]})
    return lines, entries


def ordered_keys(value, preferred=None):
    ranks = {key: index for index, key in enumerate(preferred or [])}

    def key_order(key):
        rank = ranks.get(key, float("inf"))
        if isinstance(key, (int, float)) and not isinstance(key, bool):
            return rank, 0, key
        return rank, 1, str(key)

    return sorted(value, key=key_order)


def path_name(path):
    return ".".join(str(key) for key in path)


def field_label(table_name, path):
    labels = FIELD_LABELS.get(table_name, {})
    full_name = path_name(path)
    if full_name in labels:
        return labels[full_name]
    if len(path) == 1 and path[0] in labels:
        return labels[path[0]]
    if table_name == "routeMapper.redstoneAddresses" and len(path) == 1:
        return f"第{path[0]}个流体探测红石接口地址"
    if table_name == "routeMapper.testSides":
        if len(path) == 1:
            return f"第{path[0]}个探测方向"
        if len(path) == 2:
            suffix = {"value": "方向值", "name": "方向名称"}.get(path[1], str(path[1]))
            return f"第{path[0]}个探测方向的{suffix}"
    return str(path[-1])


def collect_fields(value, table_name):
    fields = []

    def visit(current, prefix):
        preferred = FIELD_ORDER.get(table_name) if not prefix else None
        if table_name == "routeMapper.testSides" and prefix:
            preferred = ["value", "name"]
        for key in ordered_keys(current, preferred):
            next_path = prefix + [key]
            if isinstance(current[key], dict):
                visit(current[key], next_path)
            else:
                fields.append({
                    "path": next_path,
                    "name": path_name(next_path),
                    "label": field_label(table_name, next_path),
                    "value": current[key],
                })

    visit(value, [])
    return fields


def set_path(root, path, value):
    current = root
    for key in path[:-1]:
        current = current[key]
    current[path[-1]] = value


KEEP = object()


def read_new_value():
    while True:
        try:
            raw = input("new value (Enter keeps current, !clear empties): ")
        except EOFError:
            return KEEP, True
        if raw == "":
            return KEEP, False
        try:
            return parse_lua_literal(literal_text(raw)), False
        except ValueError as error:
            print(str(error))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "bec.conf"
    lines, entries = load(path)
    if not entries:
        raise SystemExit("no editable entries found")

    stopped = False
    for group_index, entry in enumerate(entries, 1):
        try:
            value = parse_lua_literal(entry["raw"])
        except ValueError as error:
            raise SystemExit(f"invalid value at {path}:{entry['index'] + 1}: {error}")

        print(f"[{group_index}/{len(entries)}] {entry['name']}\t{entry['label']}")
        if isinstance(value, dict):
            fields = collect_fields(value, entry["name"])
        else:
            fields = [{"path": [], "name": "value", "label": entry["label"], "value": value}]

        for field_index, field in enumerate(fields, 1):
            print(f"[{field_index}/{len(fields)}] {field['name']} | {field['label']} | {serialize(field['value'])}")
            new_value, eof = read_new_value()
            if eof:
                stopped = True
                break
            if new_value is not KEEP:
                if field["path"]:
                    set_path(value, field["path"], new_value)
                else:
                    value = new_value

        lines[entry["index"]] = f"{entry['name']}\t{entry['label']}\t{serialize(value)}\n"
        if stopped:
            break

    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8", newline="") as handle:
        handle.writelines(lines)
    os.replace(temporary, path)
    print(f"configuration updated: {path}")


if __name__ == "__main__":
    main()
