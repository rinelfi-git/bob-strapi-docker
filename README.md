# Docker Configuration for BOB - Strapi + PostgreSQL + Redis + LiveKit

## Dependances

### Strapi Container

| Dependance | Version | Description |
|------------|---------|-------------|
| **Node.js** | 20 LTS | Runtime JavaScript (image Debian Bookworm Slim) |
| **npm** | Latest | Gestionnaire de packages (mis a jour au build) |
| **Yarn** | Stable | Gestionnaire de packages (via corepack) |
| **msmtp** | Latest | Client SMTP leger, remplace sendmail |
| **build-essential** | Latest | Outils de compilation (gcc, g++, make) pour modules natifs |
| **python3** | Latest | Requis pour compiler certains modules Node.js (better-sqlite3, etc.) |
| **git** | Latest | Gestion de version |
| **ca-certificates** | Latest | Certificats TLS pour connexions securisees (APNs, etc.) |

**Note sur l'image de base** : Nous utilisons `node:20-bookworm-slim` (Debian) au lieu d'Alpine pour une meilleure compatibilite avec les modules natifs et le reseau. Le symlink `/usr/sbin/sendmail` → `/usr/bin/msmtp` assure la compatibilite avec Strapi.

### PostgreSQL Container

| Dependance | Version | Description |
|------------|---------|-------------|
| **PostgreSQL** | 16 (Alpine) | Base de donnees relationnelle |
| **musl-locales** | Latest | Support des locales (fr_FR.UTF-8) |
| **icu-data-full** | Latest | Donnees ICU pour collations |

### Redis Container

| Dependance | Version | Description |
|------------|---------|-------------|
| **Redis Server** | 7 (Alpine) | Base de donnees en memoire avec persistance AOF |
| **OpenSSL** | Latest | Generation securisee de mot de passe (`openssl rand -base64 32`) |

### LiveKit Container

| Dependance | Version | Description |
|------------|---------|-------------|
| **LiveKit Server** | Latest | Serveur WebRTC/RTC pour video et audio |

## Architecture

### Strapi

- **Image de base**: `node:20-bookworm-slim` (Debian)
- **Gestionnaire de packages**: Yarn (via corepack)
- **Dependances**: msmtp, build-essential, python3, git, ca-certificates
- **Port**: 1337 (configurable via `STRAPI_HOST` pour le bind)
- **Volume source**: `${STRAPI_VOLUME}` → `/app/bob`
- **Runtime**:
  - Mode `development`: `yarn install` → `yarn develop` (hot reload)
  - Mode `production`: `yarn install` → `yarn build` → `yarn start`

### PostgreSQL

- **Image de base**: `postgres:16-alpine`
- **Port**: 5432 (interne au reseau Docker)
- **Locale**: fr_FR.UTF-8 (via musl-locales)
- **Authentification**: SCRAM-SHA-256
- **Configuration personnalisee**: `/etc/postgresql/postgresql.conf`

### Redis

- **Image de base**: `redis:7-alpine`
- **Port**: 6379 (interne au reseau Docker uniquement, non expose)
- **Authentification**: Mot de passe genere automatiquement avec `openssl rand -base64 32`
- **Persistance**: AOF (Append Only File)
- **Securite**: Commandes dangereuses desactivees (`FLUSHDB`, `FLUSHALL`, `CONFIG`)

### LiveKit

- **Image de base**: `livekit/livekit-server:latest`
- **Ports**:
  - 7880: HTTP/WebSocket API
  - 7881/tcp: RTC over TCP
  - 3478/udp+tcp: TURN
  - 50000-50200/udp: RTC over UDP

## Structure des fichiers

```text
docker/
├── .env                       # Configuration centralisee (volumes, ports, environnement)
├── .env.example               # Exemple de configuration
├── docker-compose.yml         # Orchestration des services
├── README.md                  # Cette documentation
├── strapi/
│   ├── Dockerfile            # Node 20 Bookworm Slim + Yarn + msmtp + build tools
│   └── runtime.sh            # yarn install → yarn develop/build/start
├── postgresql/
│   ├── Dockerfile            # PostgreSQL 16 Alpine + musl-locales
│   ├── postgresql.conf       # Configuration PostgreSQL
│   ├── pg_hba.conf           # Configuration authentification
│   └── entrypoint.sh         # Initialisation cluster + creation user/db
├── redis/
│   ├── Dockerfile            # Redis 7 Alpine + OpenSSL
│   ├── redis.conf            # Configuration Redis securisee
│   └── entrypoint.sh         # Generation mot de passe + MAJ .env Strapi
└── livekit/
    └── livekit.yaml          # Configuration LiveKit
```

## Installation et demarrage

### 1. Configurer le fichier .env Docker

Copiez `.env.example` vers `.env` et configurez les variables :

```bash
cd /Users/macbook/workspace/BOB/docker
cp .env.example .env
```

**Variables disponibles :**

| Variable | Description | Exemple |
|----------|-------------|---------|
| `STRAPI_VOLUME` | Chemin vers le dossier Strapi | `/Users/macbook/workspace/BOB/strapi` |
| `NODE_ENV` | Environnement (`development` ou `production`) | `development` |
| `STRAPI_HOST` | IP de bind (voir section ci-dessous) | `127.0.0.1` |
| `POSTGRES_VOLUME` | Chemin vers les donnees PostgreSQL | `./data/postgresql` |
| `POSTGRES_USER` | Utilisateur PostgreSQL | `bob` |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | `votre_mot_de_passe` |
| `POSTGRES_DB` | Nom de la base de donnees | `bob` |
| `LIVEKIT_API_KEY` | Cle API LiveKit | `votre_cle` |
| `LIVEKIT_API_SECRET` | Secret API LiveKit | `votre_secret` |
| `LIVEKIT_URL` | URL LiveKit | `ws://localhost:7880` |
| `LIVEKIT_EXTERNAL_IP` | IP externe LiveKit | `votre_ip` |

#### Configuration de STRAPI_HOST (IP de bind)

Cette variable controle sur quelle interface reseau Strapi est accessible :

| Valeur | Usage | Acces |
|--------|-------|-------|
| `127.0.0.1` | **Local uniquement** (defaut) | Uniquement depuis la machine hote |
| `0.0.0.0` | **Toutes interfaces** | Accessible depuis n'importe quelle IP |
| `192.168.x.x` | **IP LAN specifique** | Pour dev mobile sur le meme reseau |

### 2. Preparer le dossier Strapi

**Supprimer node_modules** (important pour eviter les conflits de compilation) :

```bash
rm -rf /Users/macbook/workspace/BOB/strapi/node_modules
```

> **Pourquoi ?** Les modules natifs (comme `better-sqlite3`) sont compiles differemment sur macOS et Linux. En supprimant `node_modules`, le conteneur recompilera tous les modules pour son environnement Debian.

**Configurer le fichier .env de Strapi** :

Assurez-vous que le fichier `${STRAPI_VOLUME}/.env` contient les lignes suivantes :

```bash
# ========== PostgreSQL Configuration ==========
DATABASE_CLIENT=postgres
DATABASE_HOST=postgresql
DATABASE_PORT=5432
DATABASE_NAME=bob
DATABASE_USERNAME=bob
DATABASE_PASSWORD=votre_mot_de_passe

# ========== Redis Configuration ==========
REDIS_HOST=
REDIS_PORT=
REDIS_PASSWORD=
REDIS_DB=
```

> **Note**: Les valeurs Redis seront automatiquement remplies par le conteneur Redis au demarrage.

### 3. Demarrer les services

```bash
cd /Users/macbook/workspace/BOB/docker
docker compose up -d
```

L'ordre de demarrage :

1. **PostgreSQL** demarre en premier
2. PostgreSQL initialise le cluster et cree l'utilisateur/base
3. **Redis** demarre
4. Redis genere un mot de passe securise
5. Redis met a jour le fichier `.env` de Strapi
6. **LiveKit** demarre
7. **Strapi** demarre une fois PostgreSQL et Redis healthy
8. Strapi lit les credentials depuis son `.env`

### 4. Verifier les logs

```bash
# Tous les services
docker compose logs -f

# PostgreSQL uniquement
docker compose logs -f postgresql

# Redis uniquement
docker compose logs -f redis

# Strapi uniquement
docker compose logs -f strapi

# LiveKit uniquement
docker compose logs -f livekit
```

## Fonctionnement detaille

### Demarrage PostgreSQL

Au premier demarrage, le script `/usr/local/bin/entrypoint.sh` :

1. Verifie les variables d'environnement (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`)
2. Initialise le cluster avec `initdb` et locale `fr_FR.UTF-8`
3. Cree l'utilisateur et la base de donnees
4. Applique la configuration securisee (SCRAM-SHA-256)
5. Demarre PostgreSQL Server

### Demarrage Redis

Au premier demarrage, le script `/usr/local/bin/entrypoint.sh` :

1. Genere un mot de passe : `REDIS_PASSWORD=$(openssl rand -base64 32)`
2. Sauvegarde dans `/data/redis_password.txt`
3. Met a jour `/app/bob/.env` (volume Strapi) avec `sed` :
   ```bash
   REDIS_HOST=redis
   REDIS_PORT=6379
   REDIS_PASSWORD=<mot_de_passe_genere>
   REDIS_DB=0
   ```
4. Ajoute `requirepass` a la config Redis
5. Demarre Redis Server

### Demarrage Strapi

Le script `/opt/runtime.sh` execute selon `NODE_ENV` :

**Mode development** (`NODE_ENV=development`) :

```bash
cd /app/bob
yarn install    # Installe les dependances
yarn develop    # Demarre avec hot reload
```

**Mode production** (`NODE_ENV=production` ou non defini) :

```bash
cd /app/bob
yarn install    # Installe les dependances
yarn build      # Compile Strapi
yarn start      # Demarre en production
```

### Healthchecks

**PostgreSQL** est considere "healthy" quand :
```bash
pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}
```

**Redis** est considere "healthy" quand :
```bash
redis-cli -a $(cat /data/redis_password.txt) ping
```
retourne `PONG`.

## Acces aux services

- **Strapi**: `http://${STRAPI_HOST}:1337` (par defaut `http://127.0.0.1:1337`)
- **PostgreSQL**: Accessible uniquement depuis le reseau Docker interne `bob-network` (port 5432)
- **Redis**: Accessible uniquement depuis le reseau Docker interne `bob-network` (port 6379)
- **LiveKit**: `http://localhost:7880` (API), ports RTC exposes

## Commandes utiles

```bash
# Arreter les services
docker compose down

# Reconstruire les images
docker compose build --no-cache

# Redemarrer tout
docker compose restart

# Supprimer volumes (attention: perte de donnees)
docker compose down -v

# Voir les conteneurs en cours
docker compose ps

# Shell dans Strapi
docker compose exec strapi bash

# Shell dans PostgreSQL
docker compose exec postgresql sh

# Shell dans Redis
docker compose exec redis sh

# psql CLI
docker compose exec postgresql psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}

# Redis CLI
docker compose exec redis redis-cli -a $(docker compose exec redis cat /data/redis_password.txt)
```

## Securite

### PostgreSQL

- Authentification SCRAM-SHA-256
- Port non expose a l'exterieur (reseau Docker interne uniquement)
- Connexions limitees au reseau Docker

### Redis

- Mot de passe requis (`requirepass`)
- Port non expose a l'exterieur (reseau Docker interne uniquement)
- Commandes dangereuses desactivees (`FLUSHDB`, `FLUSHALL`, `CONFIG`)
- Limite memoire : 256MB avec politique LRU
- Persistance AOF pour eviter la perte de donnees

## Troubleshooting

### Strapi ne peut pas se connecter a PostgreSQL

Verifiez que :

1. Le fichier `.env` de Strapi contient bien les variables `DATABASE_*`
2. PostgreSQL est demarre et healthy : `docker compose ps`
3. Les credentials sont corrects

### Strapi ne peut pas se connecter a Redis

Verifiez que :

1. Le fichier `.env` de Strapi contient bien les variables `REDIS_*`
2. Redis est demarre et healthy : `docker compose ps`
3. Le mot de passe est correct : `grep REDIS_PASSWORD /path/to/strapi/.env`

### PostgreSQL ne demarre pas

```bash
# Verifier les logs
docker compose logs postgresql

# Verifier les permissions du volume
ls -la ${POSTGRES_VOLUME}
```

### Redis ne demarre pas

```bash
# Verifier les logs
docker compose logs redis

# Verifier la config
docker compose exec redis cat /tmp/redis.conf
```

### Reinitialiser PostgreSQL

```bash
# Arreter les services
docker compose down

# Supprimer les donnees PostgreSQL
rm -rf ${POSTGRES_VOLUME}/*

# Redemarrer (le cluster sera reinitialise)
docker compose up -d
```

### Reinitialiser le mot de passe Redis

```bash
# Arreter les services
docker compose down

# Supprimer le volume Redis
docker volume rm bob_redis-data

# Redemarrer (un nouveau mot de passe sera genere)
docker compose up -d
```

### Strapi non accessible depuis un autre appareil

Si Strapi n'est pas accessible depuis un appareil mobile ou une autre machine :

1. Verifiez `STRAPI_HOST` dans `.env` Docker - doit etre `0.0.0.0` ou votre IP LAN
2. Verifiez le pare-feu de votre machine
3. Assurez-vous que les appareils sont sur le meme reseau
4. Testez avec : `curl http://VOTRE_IP:1337/api`
