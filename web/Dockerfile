FROM node:22-bookworm-slim

# Installer yarn
RUN corepack enable && corepack prepare yarn@stable --activate

WORKDIR /app/web

# Copier l'entrypoint
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Port par defaut Next.js
EXPOSE 3000

ENTRYPOINT ["/bin/sh", "/usr/local/bin/entrypoint.sh"]
