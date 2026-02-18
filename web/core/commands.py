"""Command wrappers: invoke `dev` CLI subcommands via subprocess."""

import os
import subprocess
from collections import namedtuple

CommandResult = namedtuple("CommandResult", ["success", "output", "error"])


def run_dev(args: list[str], timeout: int = 60, stdin_data: str = None) -> CommandResult:
    """Run a dev CLI command and return a CommandResult."""
    env = os.environ.copy()
    # Ensure ~/.local/bin is in PATH so 'dev' is found
    local_bin = os.path.expanduser("~/.local/bin")
    if local_bin not in env.get("PATH", ""):
        env["PATH"] = local_bin + ":" + env.get("PATH", "")

    try:
        result = subprocess.run(
            ["dev"] + args,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            input=stdin_data,
        )
        return CommandResult(
            success=result.returncode == 0,
            output=result.stdout,
            error=result.stderr,
        )
    except subprocess.TimeoutExpired:
        return CommandResult(
            success=False,
            output="",
            error=f"Command timed out after {timeout}s",
        )
    except FileNotFoundError:
        return CommandResult(
            success=False,
            output="",
            error="'dev' command not found. Is dev-cli installed?",
        )
    except Exception as e:
        return CommandResult(
            success=False,
            output="",
            error=str(e),
        )


def new_session(
    project: str, branch: str, agent: str = "claude", yolo: bool = False, from_branch: str = "", private: bool = False
) -> CommandResult:
    """Create a new session: dev new <project> <branch> [--from base] [--agent type] [--yolo] [--private]."""
    args = ["new", project, branch]
    if from_branch:
        args.extend(["--from", from_branch])
    args.extend(["--agent", agent])
    if yolo:
        args.append("--yolo")
    if private:
        args.append("--private")
    return run_dev(args)


def kill_session(name: str) -> CommandResult:
    """Kill a session, auto-confirming prompts: dev kill <name>."""
    return run_dev(["kill", name], stdin_data="y\ny\n")


def restart_session(name: str) -> CommandResult:
    """Restart a session: dev restart <name>."""
    return run_dev(["restart", name])


def send_to_session(name: str, prompt: str) -> CommandResult:
    """Send a prompt to a session: dev send <name> <prompt>."""
    return run_dev(["send", name, prompt])


def get_logs(name: str) -> CommandResult:
    """Get session logs: dev logs <name>."""
    return run_dev(["logs", name])


def get_diff(name: str, full: bool = False) -> CommandResult:
    """Get git diff for a session: dev diff <name> [--full]."""
    args = ["diff", name]
    if full:
        args.append("--full")
    return run_dev(args)


def sync_session(name: str) -> CommandResult:
    """Sync a session: dev sync <name>."""
    return run_dev(["sync", name])


def create_pr(
    name: str, draft: bool = False, title: str = None
) -> CommandResult:
    """Create a PR for a session: dev pr <name> [--draft] [--title ...]."""
    args = ["pr", name]
    if draft:
        args.append("--draft")
    if title:
        args.extend(["--title", title])
    return run_dev(args)


def agent_add(name: str, agent_type: str) -> CommandResult:
    """Add an agent to a session: dev agent add <name> <type>."""
    return run_dev(["agent", "add", name, agent_type])


def agent_remove(name: str, agent_type: str) -> CommandResult:
    """Remove an agent from a session: dev agent remove <name> <type>."""
    return run_dev(["agent", "remove", name, agent_type])


def run_gc() -> CommandResult:
    """Run garbage collection: dev gc."""
    return run_dev(["gc"])


def run_doctor() -> CommandResult:
    """Run diagnostics: dev doctor."""
    return run_dev(["doctor"])


def task_add(project: str, description: str, branch: str = "", from_branch: str = "") -> CommandResult:
    """Add a task: dev task add <project> [branch] <description> [--from base]."""
    args = ["task", "add", project]
    if branch:
        args.append(branch)
    args.append(description)
    if from_branch:
        args.extend(["--from", from_branch])
    return run_dev(args)


def task_remove(task_id: str) -> CommandResult:
    """Remove a task: dev task rm <id>."""
    return run_dev(["task", "rm", task_id])


def task_run() -> CommandResult:
    """Run task runner single pass: dev task run."""
    return run_dev(["task", "run"], timeout=300)
