#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

[ -f "$HERMES_HOME/.env" ]        || cp "$INSTALL_DIR/.env.example"             "$HERMES_HOME/.env"
[ -f "$HERMES_HOME/config.yaml" ] || cp "$INSTALL_DIR/cli-config.yaml.example"  "$HERMES_HOME/config.yaml"
[ -f "$HERMES_HOME/SOUL.md" ]     || cp "$INSTALL_DIR/docker/SOUL.md"           "$HERMES_HOME/SOUL.md"

if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

exec hermes "$@"
