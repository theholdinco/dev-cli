#!/usr/bin/env bash
# validate-tailscale-identity.sh
# Called by sshd as AuthorizedKeysCommand to validate Tailscale identity
# Usage: validate-tailscale-identity.sh <username>
#
# Returns the user's authorized_keys if their Tailscale identity matches,
# empty output (denying login) if it doesn't.

set -euo pipefail

USERNAME="$1"
USERS_FILE="/etc/dev-cli/users.json"

# If no user registry, allow all (single-user mode)
if [[ ! -f "$USERS_FILE" ]]; then
    cat "/home/$USERNAME/.ssh/authorized_keys" 2>/dev/null || true
    exit 0
fi

# Get the expected Tailscale email for this user
EXPECTED_EMAIL=$(jq -r --arg u "$USERNAME" '.users[$u].tailscale_email // empty' "$USERS_FILE" 2>/dev/null)

# If user not in registry, deny
if [[ -z "$EXPECTED_EMAIL" ]]; then
    exit 0  # empty output = no authorized keys = denied
fi

# Check user status
USER_STATUS=$(jq -r --arg u "$USERNAME" '.users[$u].status // empty' "$USERS_FILE" 2>/dev/null)
if [[ "$USER_STATUS" != "active" ]]; then
    exit 0  # suspended users can't log in
fi

# Get the connecting client's Tailscale identity
# The SSH connection comes from a Tailscale IP (100.x.x.x)
# We use `tailscale whois` to look up who owns that IP
CLIENT_IP="${SSH_CLIENT%% *}"
if [[ -z "$CLIENT_IP" ]]; then
    # Fallback: try SSH_CONNECTION
    CLIENT_IP="${SSH_CONNECTION%% *}"
fi

if [[ -z "$CLIENT_IP" ]]; then
    exit 0  # can't determine client IP, deny
fi

# Check if it's a Tailscale IP
if [[ ! "$CLIENT_IP" =~ ^100\. ]] && [[ ! "$CLIENT_IP" =~ ^fd7a: ]]; then
    # Not a Tailscale IP — this is a direct SSH connection
    # In production, you might want to deny non-Tailscale connections entirely
    # For now, fall through to standard authorized_keys
    cat "/home/$USERNAME/.ssh/authorized_keys" 2>/dev/null || true
    exit 0
fi

# Look up the Tailscale identity
ACTUAL_EMAIL=$(tailscale whois --json "$CLIENT_IP" 2>/dev/null | jq -r '.UserProfile.LoginName // empty')

if [[ -z "$ACTUAL_EMAIL" ]]; then
    exit 0  # can't verify identity, deny
fi

# Compare
if [[ "$ACTUAL_EMAIL" == "$EXPECTED_EMAIL" ]]; then
    cat "/home/$USERNAME/.ssh/authorized_keys" 2>/dev/null || true
else
    # Identity mismatch — deny login
    logger -t dev-cli "SSH denied: $ACTUAL_EMAIL tried to log in as $USERNAME (expected $EXPECTED_EMAIL)"
    exit 0
fi
