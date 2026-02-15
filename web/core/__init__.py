"""Shared core module for dev-cli web dashboard and Telegram bot."""

import os

CONFIG_DIR = os.path.expanduser("~/.config/dev-cli")
PORT_REGISTRY = os.path.join(CONFIG_DIR, "ports.json")
GLOBAL_CONFIG = os.path.join(CONFIG_DIR, "config.json")
PROJECTS_DIR = os.path.join(CONFIG_DIR, "projects")
SECRETS_FILE = os.path.join(CONFIG_DIR, "secrets.env")
LOG_DIR = os.path.join(CONFIG_DIR, "logs")
WEB_DIR = os.path.expanduser("~/.local/share/dev-cli/web")

DEV_BIN = os.path.expanduser("~/.local/bin/dev")
