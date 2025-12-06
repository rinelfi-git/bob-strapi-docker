# Docker Configuration for BOB - Strapi + Redis

## Dépendances

### Strapi Container

| Dépendance | Version | Description |
|------------|---------|-------------|
| **Node.js** | 20 LTS | Runtime JavaScript (image Alpine pour réduire la taille) |
| **Yarn** | Pré-installé | Gestionnaire de packages (inclus dans node:20-alpine) |
| **msmtp** | Latest | Client SMTP léger pour Alpine Linux, remplace sendmail |
| **BusyBox sh** | Alpine | Shell par défaut (pas bash) |

**Note importante sur msmtp** : Alpine Linux n'inclut pas le package `sendmail` traditionnel. Nous utilisons `msmtp` comme alternative légère avec un lien symbolique `/usr/sbin/sendmail` → `/usr/bin/msmtp` pour la compatibilité avec Strapi.

### Redis Container

| Dépendance | Version | Description |
|------------|---------|-------------|
| **Redis Server** | 7 (Alpine) | Base de données en mémoire avec persistance AOF |
| **OpenSSL** | Latest | Génération sécurisée de mot de passe (`openssl rand -base64 32`) |
| **sed** | BusyBox | Édition automatique du fichier `.env` de Strapi |

### Configuration Redis

- **Persistance** : AOF (Append Only File) avec `appendfsync everysec`
- **Mémoire** : Limite de 256MB avec politique `allkeys-lru`
- **Sécurité** :
  - Authentification par mot de passe (`requirepass`)
  - Commandes désactivées : `FLUSHDB`, `FLUSHALL`, `CONFIG`
  - Protected mode désactivé (réseau Docker interne uniquement)
- **Databases** : 16 databases par défaut (DB 0-15), utilise DB 0 par défaut

## Architecture

### Strapi
- **Image de base**: Node 20 LTS (Alpine)
- **Gestionnaire de packages**: Yarn (pré-installé)
- **Dépendances**: msmtp (alternative légère à sendmail pour Alpine, avec symlink `/usr/sbin/sendmail`)
- **Port**: 1337 (accessible uniquement sur 127.0.0.1)
- **Volume source**: `${SRC_VOLUME}` → `/app/bob`
- **Runtime**: `yarn install` → `yarn build` → `yarn start`

### Redis
- **Image de base**: Redis 7 (Alpine)
- **Port**: 6379 (interne au réseau Docker uniquement, non exposé)
- **Authentification**: Mot de passe généré automatiquement avec `openssl rand -base64 32`
- **Persistance**: AOF (Append Only File)
- **Sécurité**: Commandes dangereuses désactivées (`FLUSHDB`, `FLUSHALL`, `CONFIG`)

## Structure des fichiers

```
docker/
├── .env                       # Configuration centralisée (volumes, ports, environnement)
├── .env.example               # Exemple de configuration
├── docker-compose.yml         # Orchestration des services
├── README.md                  # Cette documentation
├── strapi/
│   ├── Dockerfile            # Node 20 Alpine + Yarn + msmtp
│   └── runtime.sh            # yarn install → yarn build → yarn start
└── redis/
    ├── Dockerfile            # Redis 7 Alpine + OpenSSL
    ├── redis.conf            # Configuration Redis sécurisée
    └── entrypoint.sh         # Génération mot de passe + MAJ .env Strapi
```

## Installation et démarrage

### 1. Préparer le fichier .env de Strapi

Assurez-vous que le fichier `${SRC_VOLUME}/.env` (par défaut `/Users/macbook/workspace/BOB/strapi/.env`) contient les lignes suivantes :

```bash
# ========== Redis Configuration ==========
REDIS_HOST=
REDIS_PORT=
REDIS_PASSWORD=
REDIS_DB=
```

> **Note**: Ces valeurs seront automatiquement remplies par le conteneur Redis au démarrage.

### 2. Démarrer les services

```bash
cd /Users/macbook/workspace/BOB/docker
docker-compose up -d
```

L'ordre de démarrage :
1. **Redis** démarre en premier
2. Redis génère un mot de passe sécurisé
3. Redis met à jour le fichier `.env` de Strapi
4. **Strapi** démarre une fois Redis healthy
5. Strapi lit les credentials Redis depuis son `.env`

### 3. Vérifier les logs

```bash
# Tous les services
docker-compose logs -f

# Redis uniquement
docker-compose logs -f redis

# Strapi uniquement
docker-compose logs -f strapi
```

## Fonctionnement détaillé

### Démarrage Redis

Au premier démarrage, le script `/usr/local/bin/entrypoint.sh` :

1. Génère un mot de passe : `REDIS_PASSWORD=$(openssl rand -base64 32)`
2. Sauvegarde dans `/data/redis_password.txt`
3. Met à jour `/app/bob/.env` (volume Strapi) avec `sed` :
   ```bash
   REDIS_HOST=redis
   REDIS_PORT=6379
   REDIS_PASSWORD=<mot_de_passe_généré>
   REDIS_DB=0
   ```
4. Ajoute `requirepass` à la config Redis
5. Démarre Redis Server

### Démarrage Strapi

Le script `/opt/runtime.sh` exécute :

```bash
cd /app/bob
yarn install    # Installe les dépendances
yarn build      # Compile Strapi
yarn start      # Démarre en production
```

### Healthcheck Redis

Redis est considéré "healthy" quand :
```bash
redis-cli -a $(cat /data/redis_password.txt) ping
```
retourne `PONG`.

## Accès aux services

- **Strapi**: http://127.0.0.1:1337
- **Redis**: Accessible uniquement depuis le réseau Docker interne `bob-network`

## Récupérer le mot de passe Redis

```bash
# Voir dans les logs
docker-compose logs redis | grep "Generated Redis password"

# Lire depuis le conteneur
docker-compose exec redis cat /data/redis_password.txt

# Lire depuis le fichier .env de Strapi
grep REDIS_PASSWORD /Users/macbook/workspace/BOB/strapi/.env
```

## Utiliser Redis dans Strapi

Exemple de configuration dans `config/plugins.js` ou `config/database.js` :

```javascript
module.exports = ({ env }) => ({
  // Configuration Redis
  redis: {
    config: {
      connections: {
        default: {
          connection: {
            host: env('REDIS_HOST', 'redis'),
            port: env.int('REDIS_PORT', 6379),
            password: env('REDIS_PASSWORD'),
            db: env.int('REDIS_DB', 0),
          },
        },
      },
    },
  },
});
```

## Commandes utiles

```bash
# Arrêter les services
docker-compose down

# Reconstruire les images
docker-compose build --no-cache

# Redémarrer tout
docker-compose restart

# Supprimer volumes (⚠️ perte de données Redis)
docker-compose down -v

# Voir les conteneurs en cours
docker-compose ps

# Shell dans Strapi
docker-compose exec strapi sh

# Shell dans Redis
docker-compose exec redis sh

# Redis CLI
docker-compose exec redis redis-cli -a $(docker-compose exec redis cat /data/redis_password.txt)
```

## Sécurité Redis

- ✅ Mot de passe requis (`requirepass`)
- ✅ Port non exposé à l'extérieur (réseau Docker interne uniquement)
- ✅ Commandes dangereuses désactivées (`FLUSHDB`, `FLUSHALL`, `CONFIG`)
- ✅ Limite mémoire : 256MB avec politique LRU
- ✅ Persistance AOF pour éviter la perte de données
- ✅ Protected mode désactivé (sécurisé car réseau interne)

## Troubleshooting

### Strapi ne peut pas se connecter à Redis

Vérifiez que :
1. Le fichier `.env` de Strapi contient bien les variables `REDIS_*`
2. Redis est démarré et healthy : `docker-compose ps`
3. Le mot de passe est correct : `grep REDIS_PASSWORD /path/to/strapi/.env`

### Redis ne démarre pas

```bash
# Vérifier les logs
docker-compose logs redis

# Vérifier la config
docker-compose exec redis cat /tmp/redis.conf
```

### Réinitialiser le mot de passe Redis

```bash
# Arrêter les services
docker-compose down

# Supprimer le volume Redis (⚠️ perte de données)
docker volume rm docker_redis-data

# Redémarrer (un nouveau mot de passe sera généré)
docker-compose up -d
```
