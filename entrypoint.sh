#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

[ -f "$HERMES_HOME/.env" ]        || cp "$INSTALL_DIR/.env.example"             "$HERMES_HOME/.env"
[ -f "$HERMES_HOME/config.yaml" ] || cp "$INSTALL_DIR/cli-config.yaml.example"  "$HERMES_HOME/config.yaml"
[ -f "$HERMES_HOME/SOUL.md" ]     || cp "$INSTALL_DIR/docker/SOUL.md"           "$HERMES_HOME/SOUL.md"

# skills_sync importe des modules à la racine du repo (hermes_constants, utils…) :
# le repo doit être sur le PYTHONPATH, sinon ModuleNotFoundError au démarrage.
if [ -d "$INSTALL_DIR/skills" ]; then
    PYTHONPATH="$INSTALL_DIR" python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

exec hermes "$@"
