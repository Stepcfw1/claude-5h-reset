#!/usr/bin/env python3
"""Print the 5-hour window's resets_at from a Codex rollout JSONL file, or nothing.

Codex records rate limits in token_count events as
{"rate_limits": {"primary": {"used_percent", "window_minutes", "resets_at"}, "secondary": ...}}.
Windows are matched by duration (window_minutes == 300), not by slot, because some
builds report only a weekly window and some report none at all.
"""
import json
import sys

FIVE_HOURS_MINUTES = 300


def latest_reset(obj, found):
    """Collect resets_at only from a token_count event's rate_limits slots.

    Matching any object with window_minutes, or any object merely carrying a
    rate_limits dict, would let unrelated records override the real value, so an
    explicit "type": "token_count" is required. If a future rollout format drops that
    field, nothing is found and the caller falls back to the blind cadence.
    """
    if isinstance(obj, dict):
        limits = obj.get("rate_limits")
        if isinstance(limits, dict) and obj.get("type") == "token_count":
            for slot in ("primary", "secondary"):
                window = limits.get(slot)
                if (
                    isinstance(window, dict)
                    and window.get("window_minutes") == FIVE_HOURS_MINUTES
                    and window.get("resets_at") is not None
                ):
                    found.append(window["resets_at"])
        for value in obj.values():
            latest_reset(value, found)
    elif isinstance(obj, list):
        for value in obj:
            latest_reset(value, found)
    return found


def main(path):
    found = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                latest_reset(json.loads(line), found)
            except ValueError:
                continue
    if found:
        print(found[-1])


if __name__ == "__main__":
    main(sys.argv[1])
