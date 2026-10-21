"""Reference data fetched at most daily: model prices and built-in tool/agent names.

Only the ``export`` subcommand calls :func:`refresh`, so the dashboard's start and
``/api/refresh`` never wait on the network. Readers call :func:`load`, whose empty
values mean "use the built-in price table and hand-kept lists".
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Callable
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from pathlib import Path
from subprocess import run
from typing import Any
from urllib.request import Request, urlopen

from claude_usage import ModelPrice, prices_from_litellm

REFERENCE_MAX_AGE_H = 24
FETCH_TIMEOUT_S = 10
INIT_TIMEOUT_S = 20
MIN_TOOLS = 10  # fewer means the docs page changed shape: fall back instead
LITELLM_URL = (
    "https://raw.githubusercontent.com/BerriAI/litellm/main/"
    "model_prices_and_context_window.json"
)
TOOLS_URL = "https://code.claude.com/docs/en/tools-reference.md"
_INIT_REQUEST = {"type": "control_request", "request_id": "ui",
                 "request": {"subtype": "initialize"}}
# Never let the child run on API billing.
_KEY_VARS = ("ANTHROPIC_API_KEY", "C4_USAGE_INSIGHTS_API_KEY")
_PRICE_FIELDS = ("input", "output", "cache_write", "cache_read", "cache_write_1h")


@dataclass(frozen=True)
class Reference:
    """The cached reference data. Empty values mean "use the built-in fallback"."""

    prices: dict[str, ModelPrice]
    prices_fetched: str | None
    tools: list[str]
    agents: list[str]


def _path(home: Path) -> Path:
    return home / "reference.json"


def _read(home: Path) -> dict[str, Any]:
    try:
        data = json.loads(_path(home).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _price_from_json(d: Any) -> ModelPrice:
    if not isinstance(d, dict) or not all(
        isinstance(d.get(f), (int, float)) for f in _PRICE_FIELDS
    ):
        raise ValueError("bad price entry")
    return ModelPrice(*(float(d[f]) for f in _PRICE_FIELDS))


def _names(value: Any) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise ValueError("bad name list")
    return value


def load(home: Path) -> Reference:
    """Read ``<home>/reference.json``; a missing or unreadable file gives empty values."""
    data = _read(home)
    try:
        prices = {k: _price_from_json(v) for k, v in (data.get("prices") or {}).items()}
        fetched = data.get("prices_fetched")
        return Reference(
            prices,
            fetched if isinstance(fetched, str) and prices else None,
            _names(data.get("tools") or []),
            _names(data.get("agents") or []),
        )
    except (ValueError, AttributeError):
        return Reference({}, None, [], [])


def parse_tools(markdown: str) -> list[str]:
    """Names from the first Markdown table whose header starts ``| Tool``.

    Raises:
        ValueError: No such table, or fewer than :data:`MIN_TOOLS` names.
    """
    names: list[str] = []
    in_table = False
    for line in markdown.splitlines():
        if not in_table:
            in_table = line.startswith("| Tool ")
            continue
        if not line.startswith("|"):
            break
        if m := re.match(r"\|\s*`([^`]+)`", line):
            names.append(m.group(1))
    if len(names) < MIN_TOOLS:
        raise ValueError(f"tools table has {len(names)} names")
    return names


def _get(url: str) -> bytes:
    # The docs site answers 403 to urllib's default User-Agent.
    req = Request(url, headers={"User-Agent": "usage-insights"})
    with urlopen(req, timeout=FETCH_TIMEOUT_S) as resp:
        body: bytes = resp.read()
    return body


def fetch_prices() -> dict[str, ModelPrice]:
    data = json.loads(_get(LITELLM_URL))
    prices = prices_from_litellm(data) if isinstance(data, dict) else {}
    if not prices:
        raise ValueError("no anthropic prices in the file")
    return prices


def fetch_tools() -> list[str]:
    return parse_tools(_get(TOOLS_URL).decode("utf-8"))


def fetch_agents() -> list[str]:
    """Built-in agent names from the ``claude`` CLI's prompt-free ``initialize``.

    Closing stdin ends the CLI after it answers; no model turn runs.

    Raises:
        OSError: ``claude`` is not on PATH.
        ValueError: No ``initialize`` response with agents.
        subprocess.SubprocessError: The call timed out.
    """
    path = shutil.which("claude")
    if path is None:
        raise OSError("claude CLI not found")
    env = {k: v for k, v in os.environ.items() if k not in _KEY_VARS}
    proc = run(
        [path, "-p", "--input-format", "stream-json", "--output-format", "stream-json",
         "--verbose", "--no-session-persistence"],
        check=False,  # a non-zero exit still prints the response we need, or nothing
        input=json.dumps(_INIT_REQUEST) + "\n",
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=INIT_TIMEOUT_S,
        cwd=Path.home(),
        env=env,
        # The scheduled export runs under pythonw: no console window may flash.
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
    )
    for line in proc.stdout.splitlines():
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if not isinstance(msg, dict) or msg.get("type") != "control_response":
            continue
        resp = msg.get("response")
        if isinstance(resp, dict) and resp.get("request_id") == "ui":
            agents = (resp.get("response") or {}).get("agents") or []
            names = [a["name"] for a in agents if isinstance(a, dict)
                     and isinstance(a.get("name"), str)]
            if names:
                return names
    raise ValueError("no initialize response from the claude CLI")


def _stale(stamp: Any, now: datetime) -> bool:
    if not isinstance(stamp, str):
        return True
    try:
        return now - datetime.fromisoformat(stamp) >= timedelta(hours=REFERENCE_MAX_AGE_H)
    except (ValueError, TypeError):
        return True


_Failure = (OSError, ValueError, subprocess.SubprocessError)


def refresh(home: Path, now: datetime, progress: Callable[[str], None]) -> None:
    """Re-fetch each part older than :data:`REFERENCE_MAX_AGE_H`, then save.

    A failed fetch keeps that part's previous value and timestamp. Never raises
    for a network, parse, or CLI failure. Writes a temp file and renames it, so
    a reader never sees half a file.

    Args:
        home: The store dir holding ``reference.json``.
        now: The aware current time.
        progress: Receives one line per fetch and per failure.
    """
    data = _read(home)
    changed = False
    if _stale(data.get("prices_fetched"), now):
        try:
            data["prices"] = {k: asdict(v) for k, v in fetch_prices().items()}
            data["prices_fetched"] = now.isoformat()
            changed = True
            progress("fetched prices")
        except _Failure as exc:
            progress(f"price fetch failed, keeping the previous prices: {exc}")
    if _stale(data.get("lists_fetched"), now):
        fetched_any = False
        for key, fetch, what in (
            ("tools", fetch_tools, "tool list"),
            ("agents", fetch_agents, "agent list"),
        ):
            try:
                data[key] = fetch()
                fetched_any = True
                progress(f"fetched {what}")
            except _Failure as exc:
                progress(f"{what} fetch failed, keeping the previous list: {exc}")
        if fetched_any:
            data["lists_fetched"] = now.isoformat()
            changed = True
    if changed:
        home.mkdir(parents=True, exist_ok=True)
        tmp = home / "reference.json.tmp"
        tmp.write_text(json.dumps(data, indent=1), encoding="utf-8")
        os.replace(tmp, _path(home))
