# =============================================================================
# Dockerfile multi-stage pour Strapi (Blue-Green Deployment)
#
# Build context : ../strapi (racine du projet Strapi)
# Usage : docker compose build strapi-master
# =============================================================================

# ============================================
# Stage 1: Dependencies
# ============================================
FROM node:20-bookworm-slim AS dependency

# Installer les outils de build pour les modules natifs (bcrypt, sharp, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    git \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Activer yarn via corepack
RUN corepack enable && corepack prepare yarn@stable --activate

WORKDIR /app/bob

# Copier les fichiers de dependances en premier (layer caching)
COPY package.json yarn.lock .yarnrc.yml ./

# Installer toutes les dependances (dev incluses pour le build)
RUN yarn install

# ============================================
# Stage 2: Builder
# ============================================
FROM dependency AS builder

WORKDIR /app/bob

# Copier le code source
COPY config/ ./config/
COPY src/ ./src/
COPY database/ ./database/
COPY types/ ./types/
COPY public/robots.txt ./public/robots.txt
COPY tsconfig.json ./
COPY vite.config.js ./
COPY favicon.png ./

# Build Strapi (compile TypeScript + admin panel)
ENV NODE_ENV=production
RUN yarn build

# ============================================
# Stage 3: Production runtime
# ============================================
FROM node:20-bookworm-slim AS production

# Installer uniquement les dependances runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    msmtp \
    ca-certificates \
    curl \
    && ln -sf /usr/bin/msmtp /usr/sbin/sendmail \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Activer yarn
RUN corepack enable && corepack prepare yarn@stable --activate

WORKDIR /app/bob

# Copier les dependances installees depuis le stage deps
COPY --from=dependency /app/bob/node_modules ./node_modules
COPY --from=dependency /app/bob/package.json ./package.json
COPY --from=dependency /app/bob/yarn.lock ./yarn.lock
COPY --from=dependency /app/bob/.yarnrc.yml ./.yarnrc.yml

# Copier l'application buildee depuis le stage builder
COPY --from=builder /app/bob/dist ./dist
COPY --from=builder /app/bob/config ./config
COPY --from=builder /app/bob/src ./src
COPY --from=builder /app/bob/database ./database
COPY --from=builder /app/bob/types ./types
COPY --from=builder /app/bob/public/robots.txt ./public/robots.txt
COPY --from=builder /app/bob/favicon.png ./favicon.png
COPY --from=builder /app/bob/tsconfig.json ./tsconfig.json
COPY --from=builder /app/bob/vite.config.js ./vite.config.js

# Creer le point de montage pour les uploads (sera monte en volume)
RUN mkdir -p /app/bob/public/uploads

EXPOSE 1337

# Demarrer Strapi en mode production
CMD ["yarn", "start"]
