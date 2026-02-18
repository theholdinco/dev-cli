"""System information: IP, hostname, uptime, load, memory, port table, projects."""

import os
import platform
import subprocess

from . import PROJECTS_DIR
from .sessions import get_ip, list_sessions, slot_ports


def get_system_info() -> dict:
    """Return a dict with ip, hostname, uptime, load, and memory info."""
    info = {
        "ip": get_ip(),
        "hostname": platform.node(),
        "uptime": "",
        "load": "",
        "memory": {"total": "", "used": "", "available": ""},
    }

    # Uptime from /proc/uptime
    try:
        with open("/proc/uptime", "r") as f:
            seconds = float(f.read().split()[0])
        days = int(seconds // 86400)
        hours = int((seconds % 86400) // 3600)
        minutes = int((seconds % 3600) // 60)
        parts = []
        if days > 0:
            parts.append(f"{days}d")
        if hours > 0:
            parts.append(f"{hours}h")
        parts.append(f"{minutes}m")
        info["uptime"] = " ".join(parts)
    except (OSError, ValueError):
        try:
            result = subprocess.run(
                ["uptime", "-p"],
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                info["uptime"] = result.stdout.strip()
        except Exception:
            pass

    # Load from /proc/loadavg
    try:
        with open("/proc/loadavg", "r") as f:
            info["load"] = " ".join(f.read().split()[:3])
    except OSError:
        pass

    # Memory from free -h
    try:
        result = subprocess.run(
            ["free", "-h"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if line.startswith("Mem:"):
                    parts = line.split()
                    if len(parts) >= 4:
                        info["memory"]["total"] = parts[1]
                        info["memory"]["used"] = parts[2]
                    if len(parts) >= 7:
                        info["memory"]["available"] = parts[6]
                    break
    except Exception:
        pass

    return info


def get_port_table() -> list[dict]:
    """Return a list of dicts with name, slot, owner, frontend_port, backend_port, alive — sorted by slot."""
    sessions = list_sessions(show_all=True)
    table = []
    for s in sessions:
        ports = s.ports if s.ports else slot_ports(s.slot)
        table.append({
            "name": s.name,
            "slot": s.slot,
            "owner": s.owner,
            "frontend_port": ports.get("frontend", 0),
            "backend_port": ports.get("backend", 0),
            "alive": s.alive,
        })
    table.sort(key=lambda r: r["slot"])
    return table


def get_stats() -> dict:
    """Return a dict with system stats: cpu, memory, disk, load, uptime, and session counts."""
    info = get_system_info()
    sessions = list_sessions(show_all=True)
    alive = sum(1 for s in sessions if s.alive)
    stats = {
        "hostname": info["hostname"],
        "ip": info["ip"],
        "uptime": info["uptime"],
        "load": info["load"],
        "memory": info["memory"],
        "disk": {"total": "", "used": "", "available": "", "percent": ""},
        "cpu_count": 0,
        "sessions_total": len(sessions),
        "sessions_alive": alive,
    }

    # CPU count
    try:
        stats["cpu_count"] = os.cpu_count() or 0
    except Exception:
        pass

    # Disk usage for /home (or /)
    try:
        result = subprocess.run(
            ["df", "-h", "/home"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            lines = result.stdout.strip().splitlines()
            if len(lines) >= 2:
                parts = lines[1].split()
                if len(parts) >= 5:
                    stats["disk"]["total"] = parts[1]
                    stats["disk"]["used"] = parts[2]
                    stats["disk"]["available"] = parts[3]
                    stats["disk"]["percent"] = parts[4]
    except Exception:
        pass

    return stats


def get_projects() -> list[str]:
    """List project names from ~/.config/dev-cli/projects/ (strip .json extension)."""
    if not os.path.isdir(PROJECTS_DIR):
        return []

    projects = []
    try:
        for entry in sorted(os.listdir(PROJECTS_DIR)):
            if entry.endswith(".json"):
                projects.append(entry[:-5])
    except OSError:
        pass

    return projects
