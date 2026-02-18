"""Shared core module for dev-cli web dashboard and Telegram bot."""

import os

CONFIG_DIR = os.path.expanduser("~/.config/dev-cli")

# Prefer global registry (shared multi-user) over per-user local file
GLOBAL_PORT_REGISTRY = "/etc/dev-cli/ports.json"
_local_port_registry = os.path.join(CONFIG_DIR, "ports.json")

if os.path.isfile(GLOBAL_PORT_REGISTRY) and os.access(GLOBAL_PORT_REGISTRY, os.R_OK):
    PORT_REGISTRY = GLOBAL_PORT_REGISTRY
else:
    PORT_REGISTRY = _local_port_registry
GLOBAL_CONFIG = os.path.join(CONFIG_DIR, "config.json")
PROJECTS_DIR = os.path.join(CONFIG_DIR, "projects")
SECRETS_FILE = os.path.join(CONFIG_DIR, "secrets.env")
LOG_DIR = os.path.join(CONFIG_DIR, "logs")
WEB_DIR = os.path.expanduser("~/.local/share/dev-cli/web")

TASK_REGISTRY = os.path.join(CONFIG_DIR, "tasks.json")
DEV_BIN = os.path.expanduser("~/.local/bin/dev")
