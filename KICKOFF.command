#!/bin/bash
# Double-clic = prépare la machine puis lance Claude Code avec le prompt de kickoff P0.
cd "$(dirname "$0")"
echo "=== glasses-dashcam — kickoff P0 ==="
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.bun/bin:$HOME/.npm-global/bin:$PATH"
if ! command -v claude >/dev/null 2>&1; then
  echo "CLI 'claude' introuvable dans le PATH. Installe Claude Code puis relance ce fichier."
  echo "  npm install -g @anthropic-ai/claude-code"
  exec bash -l
fi
if ! scripts/bootstrap.sh; then
  echo; echo "bootstrap.sh a échoué — Claude Code va reprendre à partir de là."
fi
echo; echo "=== Lancement de Claude Code ==="
exec claude "$(cat docs/kickoff_prompt.txt)"
