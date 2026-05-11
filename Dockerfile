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

FROM ghcr.io/astral-sh/uv:0.11.13-python3.13-trixie AS uv_source

FROM debian:13.4

ARG HERMES_VERSION

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist \
    HERMES_HOME=/opt/data \
    TZ=Europe/Paris \
    PATH=/opt/hermes/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential gcc python3 python3-dev libffi-dev \
        nodejs npm ripgrep ffmpeg tini procps \
        git curl bash sed ca-certificates && \
    rm -rf /var/lib/apt/lists/*

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
