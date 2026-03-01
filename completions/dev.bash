# dev-cli tab completion

_dev_sessions() {
  local port_file="/etc/dev-cli/ports.json"
  [ -r "$port_file" ] || port_file="$HOME/.config/dev-cli/ports.json"
  jq -r 'keys[]' "$port_file" 2>/dev/null
}

_dev_projects() {
  local dir="$HOME/.config/dev-cli/projects"
  [ -d "$dir" ] && ls "$dir" 2>/dev/null | sed 's/\.json$//'
}

_dev() {
  local cur prev cmd
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # All available commands
  local commands="setup new ls attach kill hub dashboard ports logs url supabase pr pr-start shell worktree img projects update help status restart send diff sync gc rename private template config agent stats doctor web bot services notify mobile m task ask ghost scaffold review vibes fortune lenny"

  # Commands that take a session name as second argument
  local session_cmds="attach kill logs url supabase shell pr status restart send diff sync rename private review"

  # Commands that take a project name as second argument
  local project_cmds="new template worktree ask pr-start"

  # First argument: complete command names
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    return 0
  fi

  cmd="${COMP_WORDS[1]}"

  # ── Second argument ────────────────────────────────────────────────────
  if [ "$COMP_CWORD" -eq 2 ]; then

    # Session name completion
    if echo " $session_cmds " | grep -q " $cmd "; then
      local words
      words=$(_dev_sessions)
      # kill also accepts flags
      [ "$cmd" = "kill" ] && words="$words --all --project --force"
      [ -n "$words" ] && COMPREPLY=( $(compgen -W "$words" -- "$cur") )
      return 0
    fi

    # Project name completion
    if echo " $project_cmds " | grep -q " $cmd "; then
      local projects
      projects=$(_dev_projects)
      [ -n "$projects" ] && COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
      return 0
    fi

    # Subcommand completion
    case "$cmd" in
      img)      COMPREPLY=( $(compgen -W "ls cp grab path clean" -- "$cur") ) ;;
      web)      COMPREPLY=( $(compgen -W "setup start stop status" -- "$cur") ) ;;
      bot)      COMPREPLY=( $(compgen -W "setup start stop status" -- "$cur") ) ;;
      services) COMPREPLY=( $(compgen -W "install uninstall start stop restart status logs" -- "$cur") ) ;;
      notify)   COMPREPLY=( $(compgen -W "setup status test delay" -- "$cur") ) ;;
      task)     COMPREPLY=( $(compgen -W "add import ls approve rm prune run watch log" -- "$cur") ) ;;
      agent)    COMPREPLY=( $(compgen -W "add remove list" -- "$cur") ) ;;
      config)   COMPREPLY=( $(compgen -W "show reset project" -- "$cur") ) ;;
    esac
    return 0
  fi

  # ── Third argument and beyond ──────────────────────────────────────────

  # kill --project <project-name>
  if [ "$cmd" = "kill" ] && [ "$prev" = "--project" ]; then
    local projects
    projects=$(_dev_projects)
    [ -n "$projects" ] && COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
    return 0
  fi

  # supabase <session> <subcommand>
  if [ "$cmd" = "supabase" ] && [ "$COMP_CWORD" -eq 3 ]; then
    COMPREPLY=( $(compgen -W "start stop reset status" -- "$cur") )
    return 0
  fi

  # agent <subcommand> <session>
  if [ "$cmd" = "agent" ] && [ "$COMP_CWORD" -eq 3 ]; then
    local sessions
    sessions=$(_dev_sessions)
    [ -n "$sessions" ] && COMPREPLY=( $(compgen -W "$sessions" -- "$cur") )
    return 0
  fi

  # agent add/remove <session> <type>
  if [ "$cmd" = "agent" ] && [ "$COMP_CWORD" -eq 4 ]; then
    case "${COMP_WORDS[2]}" in
      add|remove) COMPREPLY=( $(compgen -W "claude codex" -- "$cur") ) ;;
    esac
    return 0
  fi

  # config project <project-name>
  if [ "$cmd" = "config" ] && [ "${COMP_WORDS[2]:-}" = "project" ] && [ "$COMP_CWORD" -eq 3 ]; then
    local projects
    projects=$(_dev_projects)
    [ -n "$projects" ] && COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
    return 0
  fi

  # services logs <service>
  if [ "$cmd" = "services" ] && [ "${COMP_WORDS[2]:-}" = "logs" ] && [ "$COMP_CWORD" -eq 3 ]; then
    COMPREPLY=( $(compgen -W "web bot task-runner" -- "$cur") )
    return 0
  fi

  # task add <project>
  if [ "$cmd" = "task" ] && [ "${COMP_WORDS[2]:-}" = "add" ] && [ "$COMP_CWORD" -eq 3 ]; then
    local projects
    projects=$(_dev_projects)
    [ -n "$projects" ] && COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
    return 0
  fi

  # task import <file> [flags] — complete flags after the file arg
  if [ "$cmd" = "task" ] && [ "${COMP_WORDS[2]:-}" = "import" ]; then
    if [ "$prev" = "--project" ]; then
      local projects
      projects=$(_dev_projects)
      [ -n "$projects" ] && COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
      return 0
    fi
    if [[ "$cur" == -* ]]; then
      COMPREPLY=( $(compgen -W "--project --from --private --dry-run" -- "$cur") )
      return 0
    fi
    # Default to file completion (handled by bash)
    return 0
  fi

  # task ls <flags>
  if [ "$cmd" = "task" ] && [ "${COMP_WORDS[2]:-}" = "ls" ]; then
    COMPREPLY=( $(compgen -W "--all --pending --running --done --failed --pr-created --plan-review" -- "$cur") )
    return 0
  fi

  # task add <project> <desc> <flags>
  if [ "$cmd" = "task" ] && [ "${COMP_WORDS[2]:-}" = "add" ] && [ "$COMP_CWORD" -ge 4 ]; then
    COMPREPLY=( $(compgen -W "--from --private --plan" -- "$cur") )
    return 0
  fi

  # task prune <flags>
  if [ "$cmd" = "task" ] && [ "${COMP_WORDS[2]:-}" = "prune" ]; then
    COMPREPLY=( $(compgen -W "--failed --all-finished --dry-run" -- "$cur") )
    return 0
  fi

  return 0
}

complete -F _dev dev
complete -F _dev d
