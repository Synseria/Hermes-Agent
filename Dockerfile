# ==============================================================================
# Image Hermes Agent — k3s-ready (non-root, readOnlyRootFilesystem-compatible)
# ==============================================================================
# Déploiement k3s recommandé côté Pod :
#   securityContext:
#     runAsNonRoot: true
#     runAsUser: 1001
#     fsGroup: 1001
#     readOnlyRootFilesystem: true
#     allowPrivilegeEscalation: false
#     capabilities: { drop: [ALL] }
#   volumes:
#     - PVC monté sur /opt/data       (state Hermes)
#     - emptyDir sur /tmp             (fichiers temporaires Python/Node)
#     - emptyDir medium=Memory sur /dev/shm (Chromium ~256Mi)
# ==============================================================================

FROM ghcr.io/astral-sh/uv:0.12.5-python3.13-trixie AS uv_source

# Node LTS officiel : Debian trixie ne fournit que nodejs 20 / npm 9,
# incompatibles avec les engines de hermes-agent (node >=22.22, npm >=11.17 ou <11.10).
# Rester sur une version PAIRE (LTS) : le bump Dependabot vers node 26 (impair,
# non-LTS) a fait pendre `npx playwright install` et bloqué tous les builds
# du 13 au 26 août (timeout 6 h par run). Versions impaires ignorées via
# .github/dependabot.yml.
FROM node:24-trixie-slim AS node_source

FROM debian:13.6

ARG HERMES_VERSION

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # CRITIQUE : sans ce chemin, uv télécharge l'interpréteur requis par
    # l'upstream (ex. CPython 3.11) dans ~/.local/share/uv = /opt/data,
    # masqué au runtime par le volume monté sur /opt/data → symlink du venv
    # pendu → fallback silencieux sur le python système sans dépendances
    # (ModuleNotFoundError au démarrage).
    UV_PYTHON_INSTALL_DIR=/opt/hermes/.uv-python \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist \
    HERMES_HOME=/opt/data \
    TZ=Europe/Paris \
    PATH=/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential gcc python3 python3-dev libffi-dev \
        ripgrep ffmpeg tini procps \
        git curl bash sed ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=node_source /usr/local/bin/node /usr/local/bin/node
COPY --from=node_source /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    node --version && npm --version

RUN useradd -u 1001 -m -d /opt/data -s /bin/bash hermes

COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

RUN git clone --depth 1 --branch "v${HERMES_VERSION}" \
        https://github.com/NousResearch/hermes-agent.git . && \
    rm -rf .git

RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    (cd scripts/whatsapp-bridge && npm install --prefer-offline --no-audit) && \
    (cd web && npm install --prefer-offline --no-audit) && \
    npm cache clean --force

RUN cd web && npm run build && rm -rf node_modules

RUN chown -R hermes:hermes /opt/hermes
USER hermes
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

USER root
COPY --chmod=0755 entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh

VOLUME ["/opt/data"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD hermes --version || exit 1

USER hermes
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
