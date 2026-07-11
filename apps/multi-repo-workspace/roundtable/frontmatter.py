"""Lenient, READ-ONLY frontmatter reader — roundtable only needs `title` for display.

roundtable never writes plan files, so there is no `dump`.

Cross-reference: forked at birth from docket
(apps/multi-repo-plan-runner/docket/frontmatter.py).
"""

from __future__ import annotations


def parse(text: str) -> tuple[dict[str, str], str]:
    """Split a leading '---' fenced block of flat `key: value` lines from the body.

    Returns (meta, body). No frontmatter -> ({}, text). Values are str. Robust to CRLF
    and to a missing trailing newline. Richer YAML (lists, nesting) is ignored — we read
    the flat scalar keys we can and skip the rest.
    """
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized.startswith("---\n") and normalized != "---":
        return {}, text

    lines = normalized.split("\n")
    # lines[0] is the opening '---'; find the closing fence.
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, text

    meta: dict[str, str] = {}
    for line in lines[1:end]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            meta[key] = value

    body = "\n".join(lines[end + 1 :])
    return meta, body
