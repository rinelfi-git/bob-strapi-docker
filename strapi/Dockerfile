# Utiliser Node 20 LTS sur Debian Bookworm Slim
FROM node:20-bookworm-slim

# Installer les dépendances de build et outils nécessaires
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials pour les modules natifs Node.js
    build-essential \
    python3 \
    # Pour msmtp (alternative légère à sendmail)
    msmtp \
    # Outils utiles
    git \
    ca-certificates \
    && ln -sf /usr/bin/msmtp /usr/sbin/sendmail \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Mettre à jour npm et npx à la dernière version
RUN npm install -g npm@latest

# Activer yarn via corepack
RUN corepack enable && corepack prepare yarn@stable --activate

# Définir le répertoire de travail
WORKDIR /app/bob

# Copier le script runtime dans /opt
COPY runtime.sh /opt/runtime.sh
RUN chmod +x /opt/runtime.sh

# Exposer le port 1337 (port par défaut de Strapi)
EXPOSE 1337

# Point d'entrée : exécuter le script runtime
ENTRYPOINT ["/opt/runtime.sh"]
