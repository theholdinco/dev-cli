#!/usr/bin/env bash
###############################################################################
# Example: Customized monorepo setup hook
# Location: ~/.config/dev-cli/hooks/klyra/setup.sh
#
# This shows what you can do after dev init generates the initial hook.
# You can add custom logic, conditionals, shared secrets, etc.
###############################################################################

set -euo pipefail

echo "Setting up Klyra monorepo (slot $DEV_SLOT)..."

# ── Shared secrets (same across all packages) ────────────────
# Source from a secure file so they're not in the hook script
SHARED_SECRETS="$HOME/.config/dev-cli/secrets/klyra.env"
if [ -f "$SHARED_SECRETS" ]; then
  source "$SHARED_SECRETS"
  echo "  ✓ Loaded shared secrets"
fi

# ── packages/web (Next.js frontend) ─────────────────────────
if [ -d "$DEV_WORKTREE/packages/web" ]; then
  cat > "$DEV_WORKTREE/packages/web/.env" << ENVEOF
NODE_ENV=development
PORT=$DEV_FRONTEND_PORT
NEXT_PUBLIC_PORT=$DEV_FRONTEND_PORT
NEXT_PUBLIC_API_URL=http://localhost:$DEV_BACKEND_PORT
NEXT_PUBLIC_WS_URL=ws://localhost:$DEV_BACKEND_PORT

NEXT_PUBLIC_SUPABASE_URL=http://localhost:$DEV_SUPA_API_PORT
NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}

NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=${STRIPE_PK:-}
NEXT_PUBLIC_APP_URL=http://$DEV_IP:$DEV_FRONTEND_PORT
ENVEOF
  echo "  ✓ packages/web/.env"
fi

# ── packages/api (Express backend) ──────────────────────────
if [ -d "$DEV_WORKTREE/packages/api" ]; then
  cat > "$DEV_WORKTREE/packages/api/.env" << ENVEOF
NODE_ENV=development
PORT=$DEV_BACKEND_PORT

SUPABASE_URL=http://localhost:$DEV_SUPA_API_PORT
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_KEY:-}
SUPABASE_DB_URL=postgresql://postgres:postgres@localhost:$DEV_SUPA_DB_PORT/postgres

REDIS_URL=redis://localhost:6379
STRIPE_SECRET_KEY=${STRIPE_SK:-}
STRIPE_WEBHOOK_SECRET=${STRIPE_WH:-}

JWT_SECRET=${JWT_SECRET:-dev-secret-slot-$DEV_SLOT}
CORS_ORIGIN=http://$DEV_IP:$DEV_FRONTEND_PORT
ENVEOF
  echo "  ✓ packages/api/.env"
fi

# ── packages/workers (background jobs) ──────────────────────
if [ -d "$DEV_WORKTREE/packages/workers" ]; then
  cat > "$DEV_WORKTREE/packages/workers/.env" << ENVEOF
NODE_ENV=development

SUPABASE_URL=http://localhost:$DEV_SUPA_API_PORT
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_KEY:-}
SUPABASE_DB_URL=postgresql://postgres:postgres@localhost:$DEV_SUPA_DB_PORT/postgres

REDIS_URL=redis://localhost:6379
ENVEOF
  echo "  ✓ packages/workers/.env"
fi

# ── packages/shared (library — no env needed) ───────────────
# Nothing to do, just noting it exists

# ── Root .env.local ─────────────────────────────────────────
cat > "$DEV_WORKTREE/.env.local" << ENVEOF
NODE_ENV=development
DEV_SLOT=$DEV_SLOT
ENVEOF
echo "  ✓ .env.local (root)"

# ── Patch Supabase config ────────────────────────────────────
if [ -f "$DEV_WORKTREE/supabase/config.toml" ]; then
  cp "$DEV_WORKTREE/supabase/config.toml" "$DEV_WORKTREE/supabase/config.toml.original" 2>/dev/null || true
  sed -i "s/^port = 54321$/port = $DEV_SUPA_API_PORT/" "$DEV_WORKTREE/supabase/config.toml"
  sed -i "s/^port = 54322$/port = $DEV_SUPA_DB_PORT/" "$DEV_WORKTREE/supabase/config.toml"
  sed -i "s/^port = 54323$/port = $DEV_SUPA_STUDIO_PORT/" "$DEV_WORKTREE/supabase/config.toml"
  echo "  ✓ supabase/config.toml ports patched"
fi

# ── Custom: Symlink shared configs ───────────────────────────
# Example: if you have a shared tsconfig or eslint config
# ln -sf "$DEV_WORKTREE/packages/shared/tsconfig.base.json" "$DEV_WORKTREE/tsconfig.json"

echo ""
echo "Klyra monorepo setup complete!"
echo "  Frontend: http://$DEV_IP:$DEV_FRONTEND_PORT"
echo "  Backend:  http://$DEV_IP:$DEV_BACKEND_PORT"
