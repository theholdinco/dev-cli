"""Task management: read/write tasks.json for the automated task queue."""

import json
import os
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from . import CONFIG_DIR

TASK_REGISTRY = os.path.join(CONFIG_DIR, "tasks.json")


@dataclass
class TaskInfo:
    id: str
    project: str
    branch: str
    description: str
    status: str  # pending, running, done, failed
    from_branch: Optional[str] = None
    session: Optional[str] = None
    pr_url: Optional[str] = None
    created: str = ""
    started: Optional[str] = None
    completed: Optional[str] = None


def _read_registry() -> dict:
    """Read tasks.json and return parsed data."""
    if not os.path.isfile(TASK_REGISTRY):
        return {"tasks": [], "next_id": 1}
    try:
        with open(TASK_REGISTRY, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {"tasks": [], "next_id": 1}


def _write_registry(data: dict) -> None:
    """Atomically write tasks.json."""
    tmp = TASK_REGISTRY + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, TASK_REGISTRY)


def _task_from_dict(d: dict) -> TaskInfo:
    """Convert a dict entry to a TaskInfo."""
    return TaskInfo(
        id=str(d.get("id", "")),
        project=d.get("project", ""),
        branch=d.get("branch", ""),
        description=d.get("description", ""),
        status=d.get("status", "pending"),
        from_branch=d.get("from_branch"),
        session=d.get("session"),
        pr_url=d.get("pr_url"),
        created=d.get("created", ""),
        started=d.get("started"),
        completed=d.get("completed"),
    )


def list_tasks() -> list[TaskInfo]:
    """Return all tasks from the registry."""
    data = _read_registry()
    return [_task_from_dict(t) for t in data.get("tasks", [])]


def get_task(task_id: str) -> Optional[TaskInfo]:
    """Get a single task by ID."""
    for task in list_tasks():
        if task.id == task_id:
            return task
    return None


def _generate_branch(task_id: str, description: str) -> str:
    """Generate a branch name from task ID and description slug."""
    import re
    slug = re.sub(r"[^a-z0-9]+", "-", description.lower()).strip("-")[:50]
    return f"task-{task_id}/{slug}"


def add_task(project: str, description: str, branch: str = "", from_branch: str = "") -> TaskInfo:
    """Add a new task and return it. Branch is auto-generated if not provided."""
    data = _read_registry()
    task_id = str(data.get("next_id", 1))
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if not branch:
        branch = _generate_branch(task_id, description)

    entry = {
        "id": task_id,
        "project": project,
        "branch": branch,
        "description": description,
        "from_branch": from_branch or None,
        "status": "pending",
        "session": None,
        "pr_url": None,
        "created": now,
        "started": None,
        "completed": None,
    }
    data.setdefault("tasks", []).append(entry)
    data["next_id"] = int(task_id) + 1
    _write_registry(data)
    return _task_from_dict(entry)


def remove_task(task_id: str) -> bool:
    """Remove a task by ID. Kills the session if running. Returns True if found and removed."""
    data = _read_registry()
    original_len = len(data.get("tasks", []))

    # Find the task and kill its session if it has one
    for t in data.get("tasks", []):
        if str(t.get("id", "")) == task_id and t.get("session"):
            subprocess.run(
                ["dev", "kill", t["session"]],
                capture_output=True, timeout=30,
            )
            break

    data["tasks"] = [t for t in data.get("tasks", []) if str(t.get("id", "")) != task_id]
    if len(data["tasks"]) < original_len:
        _write_registry(data)
        return True
    return False


def task_status_color(status: str) -> str:
    """Return a CSS color class for a task status."""
    return {
        "pending": "yellow",
        "running": "blue",
        "pr-created": "cyan",
        "done": "green",
        "failed": "red",
    }.get(status, "gray")


def human_readable_age(iso_str: str) -> str:
    """Convert an ISO datetime string to a human-readable age."""
    if not iso_str:
        return ""
    try:
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
