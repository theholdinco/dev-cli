"""Session management: read ports.json, enrich with tmux/git info."""

import json
import os
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from . import PORT_REGISTRY


@dataclass
class SessionInfo:
    name: str
    project: str
    branch: str
    slot: int
    agents: list = field(default_factory=list)
    ports: dict = field(default_factory=dict)
    owner: str = ""
    created: str = ""
    worktree: str = ""
    alive: bool = False
    age: str = ""
    git_dirty: int = 0
    git_ahead: int = 0


def slot_ports(slot: int) -> dict:
    """Compute port assignments for a given slot number."""
    return {
        "frontend": 3001 + slot - 1,
        "backend": 4001 + slot - 1,
        "supa_api": 54321 + (slot - 1) * 10,
        "supa_db": 54322 + (slot - 1) * 10,
        "supa_studio": 54323 + (slot - 1) * 10,
    }


def is_alive(name: str) -> bool:
    """Check if a tmux session with the given name exists."""
    result = subprocess.run(
        ["tmux", "has-session", "-t", name],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def get_preview(name: str, lines: int = 8) -> str:
    """Capture recent output from a tmux session pane."""
    result = subprocess.run(
        ["tmux", "capture-pane", "-t", f"{name}:0", "-p", "-S", f"-{lines}"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout
    return ""


def get_git_info(path: str) -> tuple[int, int]:
    """Return (dirty_count, ahead_count) for a worktree path."""
    dirty = 0
    ahead = 0

    if not path or not os.path.isdir(path):
        return dirty, ahead

    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True,
            text=True,
            cwd=path,
        )
        if result.returncode == 0:
            dirty = len([l for l in result.stdout.strip().splitlines() if l.strip()])
    except Exception:
        pass

    try:
        result = subprocess.run(
            ["git", "rev-list", "--count", "@{u}..HEAD"],
            capture_output=True,
            text=True,
            cwd=path,
        )
        if result.returncode == 0:
            ahead = int(result.stdout.strip())
    except Exception:
        pass

    return dirty, ahead


def human_readable_age(iso_str: str) -> str:
    """Convert an ISO datetime string to a human-readable age like '2h 30m' or '3d 5h'."""
    if not iso_str:
        return ""

    try:
        # Handle both timezone-aware and naive ISO strings
        created = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        delta = now - created
    except (ValueError, TypeError):
        return ""

    total_seconds = int(delta.total_seconds())
    if total_seconds < 0:
        return "0m"

    days = total_seconds // 86400
    hours = (total_seconds % 86400) // 3600
    minutes = (total_seconds % 3600) // 60

    if days > 0:
        return f"{days}d {hours}h"
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def get_ip() -> str:
    """Get the machine IP, preferring Tailscale, falling back to hostname -I."""
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().splitlines()[0]
    except FileNotFoundError:
        pass

    try:
        result = subprocess.run(
            ["hostname", "-I"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split()[0]
    except Exception:
        pass

    return "127.0.0.1"


def list_sessions(show_all: bool = True) -> list[SessionInfo]:
    """Read ports.json and return a list of SessionInfo objects sorted by slot."""
    if not os.path.isfile(PORT_REGISTRY):
        return []

    try:
        with open(PORT_REGISTRY, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return []

    sessions = []
    for name, entry in data.items():
        slot = entry.get("slot", 0)
        alive = is_alive(name)

        if not show_all and not alive:
            continue

        ports = entry.get("ports", slot_ports(slot))
        worktree = entry.get("worktree", entry.get("path", ""))
        created = entry.get("created", "")

        dirty, ahead = get_git_info(worktree)

        session = SessionInfo(
            name=name,
            project=entry.get("project", ""),
            branch=entry.get("branch", ""),
            slot=slot,
            agents=entry.get("agents", []),
            ports=ports,
            owner=entry.get("owner", ""),
            created=created,
            worktree=worktree,
            alive=alive,
            age=human_readable_age(created),
            git_dirty=dirty,
            git_ahead=ahead,
        )
        sessions.append(session)

    sessions.sort(key=lambda s: s.slot)
    return sessions


def get_session(name: str) -> Optional[SessionInfo]:
    """Find a session by name with partial matching: exact, then prefix, then substring."""
    sessions = list_sessions(show_all=True)

    if not sessions:
        return None

    # Exact match
    for s in sessions:
        if s.name == name:
            return s

    # Prefix match
    matches = [s for s in sessions if s.name.startswith(name)]
    if len(matches) == 1:
        return matches[0]

    # Substring match
    matches = [s for s in sessions if name in s.name]
    if len(matches) == 1:
        return matches[0]

    return None
