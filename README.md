# Docker Configuration for BOB - Blue-Green Deployment

## Vue d'ensemble

L'infrastructure Docker de BOB utilise un **deploiement blue-green** pour Strapi, permettant des mises a jour **zero-downtime**. Deux conteneurs Strapi (`strapi-master` et `strapi-slave`) partagent le meme volume d'uploads et la meme base de donnees. Nginx bascule automatiquement le trafic vers le conteneur disponible.

## Architecture

```
                         ┌──────────────────────┐
                         │    Nginx (host)       │
                         │    :80 / :443         │
                         └──────────┬────────────┘
                                    │
                          upstream strapi_backend
                       ┌────────────┴────────────┐
                       │                         │
                  :1337 (principal)         :1338 (backup)
              ┌────────┴────────┐     ┌──────────┴──────────┐
              │  strapi-master  │     │   strapi-slave       │
              │  CRON_ENABLED=  │     │   CRON_ENABLED=      │
              │  true           │     │   false               │
              └────────┬────────┘     └──────────┬───────────┘
                       │                         │
                       └────────────┬────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │   Volume partage (uploads)    │
                    │   ${UPLOADS_VOLUME} →          │
                    │   /app/bob/public/uploads      │
                    └───────────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
        ┌─────┴─────┐        ┌─────┴─────┐        ┌──────┴──────┐
        │ PostgreSQL │        │   Redis   │        │   LiveKit   │
        │ :5432      │        │   :6379   │        │   :7880     │
        └───────────┘        └───────────┘        └─────────────┘

                         Reseau Docker : bob-network
```

### Comment ca marche

- **strapi-master** (port 1337) est le serveur **principal** dans Nginx
- **strapi-slave** (port 1338) est le serveur **backup** dans Nginx
- En temps normal, seul `strapi-master` tourne. `strapi-slave` est eteint
- Pendant un deploiement, `strapi-slave` prend temporairement le relais
- Nginx bascule **automatiquement** via `proxy_next_upstream` (pas besoin de recharger la config)
- Seul `strapi-master` execute les **crons** (rappels pre/post pret)

## Services

| Service | Image | Port host | Description |
|---------|-------|-----------|-------------|
| `strapi-master` | `bob-strapi:latest` | 1337 | Instance Strapi principale (crons actifs) |
| `strapi-slave` | `bob-strapi:latest` | 1338 | Instance Strapi backup (crons desactives). Profil: `blue-green` |
| `strapi-dev` | Dockerfile.dev | 1337 | Mode developpement avec hot-reload. Profil: `dev` |
| `postgresql` | postgres:16-alpine | 5432 (interne) | Base de donnees |
| `redis` | redis:7-alpine | 6379 (interne) | Cache et files d'attente (Bull) |
| `livekit` | livekit-server:latest | 7880, 7881, 3478, 50000-50200 | Serveur WebRTC |

## Structure des fichiers

```
docker/
├── .env                          # Variables d'environnement (volumes, mots de passe, etc.)
├── .env.example                  # Exemple de .env
├── docker-compose.yml            # Orchestration de tous les services
├── deploy.sh                     # Script de deploiement blue-green
├── README.md                     # Cette documentation
├── strapi-data.sh                # Script de backup/restore
├── strapi/
│   ├── Dockerfile                # Multi-stage build pour la production
│   └── Dockerfile.dev            # Image dev (volume mount + yarn develop)
├── postgresql/
│   ├── Dockerfile                # PostgreSQL 16 Alpine + locales fr_FR
│   ├── postgresql.conf           # Configuration PostgreSQL
│   ├── pg_hba.conf               # Configuration authentification
│   └── entrypoint.sh             # Initialisation cluster + creation user/db
├── redis/
│   ├── Dockerfile                # Redis 7 Alpine
│   ├── redis.conf                # Configuration Redis securisee
│   └── entrypoint.sh             # Demarrage avec mot de passe
├── nginx/
│   └── bob.strapi-pro.com.conf   # Config Nginx avec upstream blue-green
└── livekit/
    └── livekit.yaml              # Configuration LiveKit
```

## Installation

### 1. Configurer les variables d'environnement

```bash
cd docker
cp .env.example .env
```

Editez `.env` avec vos valeurs :

| Variable | Description | Exemple |
|----------|-------------|---------|
| `UPLOADS_VOLUME` | **Chemin host** pour les uploads partages entre master et slave | `/var/www/bob/uploads` |
| `STRAPI_VOLUME` | Chemin vers le projet Strapi (mode dev uniquement) | `/home/user/bob/strapi` |
| `STRAPI_VERSION` | Tag de l'image Docker Strapi | `latest` |
| `STRAPI_HOST` | IP de bind pour les ports exposes | `0.0.0.0` |
| `REDIS_PASSWORD` | Mot de passe Redis (obligatoire, plus d'auto-generation) | `monMotDePasse123` |
| `POSTGRES_VOLUME` | Chemin host pour les donnees PostgreSQL | `/var/www/bob/data/postgresql` |
| `POSTGRES_USER` | Utilisateur PostgreSQL | `BoB` |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | `monMotDePasse` |
| `POSTGRES_DB` | Nom de la base de donnees | `BoB` |
| `LIVEKIT_EXTERNAL_IP` | IP externe du serveur LiveKit | `72.60.132.74` |
| `LIVEKIT_API_KEY` | Cle API LiveKit | `livekit` |
| `LIVEKIT_API_SECRET` | Secret API LiveKit (min 32 caracteres) | `sTDqA5LKNRM5...` |
| `LIVEKIT_URL` | URL WebSocket LiveKit | `ws://72.60.132.74:7880` |

### 2. Configurer le .env de Strapi

Le fichier `strapi/.env` doit contenir les credentials de connexion aux services :

```env
# Les variables REDIS_* doivent correspondre a ce qui est dans docker/.env
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=<meme mot de passe que REDIS_PASSWORD dans docker/.env>
REDIS_DB=0

# Les variables DATABASE_* doivent correspondre a docker/.env
DATABASE_CLIENT=postgres
DATABASE_HOST=postgresql
DATABASE_PORT=5432
DATABASE_NAME=BoB
DATABASE_USERNAME=BoB
DATABASE_PASSWORD=<meme mot de passe que POSTGRES_PASSWORD dans docker/.env>
```

> **Important** : Le mot de passe Redis n'est plus auto-genere par le conteneur Redis. Il faut le definir manuellement dans `docker/.env` ET dans `strapi/.env`.

### 3. Preparer le volume d'uploads

Si vous migrez depuis l'ancien setup (volume monte du projet complet), copiez les uploads existants vers le chemin dedie :

```bash
# Creer le dossier d'uploads
mkdir -p /chemin/vers/uploads

# Copier les uploads existants
cp -a /chemin/vers/strapi/public/uploads/* /chemin/vers/uploads/

# Mettre UPLOADS_VOLUME dans docker/.env
# UPLOADS_VOLUME=/chemin/vers/uploads
```

### 4. Installer la config Nginx

Nginx tourne **sur le host** (pas dans Docker). Copiez la config :

```bash
# Copier la config du site
sudo cp docker/nginx/bob.strapi-pro.com.conf /etc/nginx/conf.d/

# Tester et recharger
sudo nginx -t && sudo nginx -s reload
```

### 5. Premier demarrage

```bash
cd docker

# Build l'image Strapi et demarrer les services
docker compose build strapi-master
docker compose up -d
```

L'ordre de demarrage automatique :
1. **PostgreSQL** demarre → healthcheck `pg_isready`
2. **Redis** demarre → healthcheck `redis-cli ping`
3. **LiveKit** demarre
4. **strapi-master** demarre une fois les dependances healthy → healthcheck `curl /_health`

## Deploiement (zero-downtime)

### Workflow automatique

```bash
cd docker
./deploy.sh
```

Le script execute automatiquement les 7 etapes :

```
Etape 1/7 : Build de la nouvelle image Docker
            (multi-stage : deps → build → production)
                    │
Etape 2/7 : Demarrage de strapi-slave avec la nouvelle image
            (nginx l'a en backup, ne lui envoie rien)
                    │
Etape 3/7 : Attente du healthcheck de strapi-slave
            (curl http://localhost:1337/_health toutes les 15s, max 180s)
                    │
           ECHEC ?──┤──→ Deploiement annule. Master inchange, rien ne casse.
                    │
Etape 4/7 : Arret de strapi-master
            → Nginx detecte le fail et bascule AUTO sur slave (backup)
                    │
Etape 5/7 : Redemarrage de strapi-master avec la nouvelle image
                    │
Etape 6/7 : Attente du healthcheck de strapi-master
                    │
           ECHEC ?──┤──→ Slave continue de servir le trafic.
                    │     Intervenir manuellement pour diagnostiquer.
                    │
Etape 7/7 : Arret de strapi-slave
            → Master reprend le role principal
                    │
            DEPLOIEMENT TERMINE
```

### Commandes du script

```bash
# Deploiement complet zero-downtime
./deploy.sh

# Voir l'etat des conteneurs
./deploy.sh --status

# Build l'image sans deployer (pour tester)
./deploy.sh --build-only

# Aide
./deploy.sh --help
```

### Securite du deploiement

| Etape d'echec | Impact | Action |
|----------------|--------|--------|
| Etape 3 (slave ne demarre pas) | **Aucun**. Master n'a pas ete touche. | Le slave defaillant est arrete. Investiguer les logs. |
| Etape 6 (master ne redemarre pas) | **Degrade**. Slave sert le trafic. | Le trafic fonctionne via slave. Corriger et relancer master manuellement. |

## Mode developpement

Le mode dev utilise l'ancien setup avec volume mount du projet complet et hot-reload :

```bash
cd docker

# Demarrer en mode dev (strapi-master ne demarre PAS, pas de conflit de port)
docker compose --profile dev up -d strapi-dev

# Voir les logs
docker compose --profile dev logs -f strapi-dev
```

> **Note** : `strapi-dev` et `strapi-master` utilisent tous les deux le port 1337 sur le host. Ne les lancez pas en meme temps.

Le mode dev :
- Monte `${STRAPI_VOLUME}:/app/bob` (projet complet en volume)
- Execute `runtime.sh` : `yarn install` → `yarn develop`
- Les modifications de code sont visibles immediatement (hot-reload)

## Dockerfile multi-stage (production)

L'image de production est construite en 3 etapes pour minimiser la taille et maximiser le cache :

```
┌─────────────────────────────────────────────────────────┐
│ Stage 1: deps                                           │
│ node:20-bookworm-slim + build-essential + python3       │
│ COPY package.json yarn.lock .yarnrc.yml                 │
│ RUN yarn install                                        │
│                                                         │
│ → Couche cachee tant que les deps ne changent pas       │
├─────────────────────────────────────────────────────────┤
│ Stage 2: builder                                        │
│ COPY config/ src/ database/ types/ tsconfig.json ...    │
│ RUN yarn build                                          │
│                                                         │
│ → Compile TypeScript + build admin panel React           │
├─────────────────────────────────────────────────────────┤
│ Stage 3: production                                     │
│ node:20-bookworm-slim (image propre, pas de build tools)│
│ COPY --from=deps node_modules                           │
│ COPY --from=builder dist/ config/ src/ ...              │
│ CMD ["yarn", "start"]                                   │
│                                                         │
│ → Image finale legere, demarrage instantane             │
└─────────────────────────────────────────────────────────┘
```

**Difference avec l'ancien setup** : Plus de `yarn install` ni `yarn build` au demarrage. L'image contient tout. Le conteneur demarre en quelques secondes au lieu de plusieurs minutes.

## Configuration Nginx

Nginx tourne sur le host et utilise un upstream avec **failover automatique** :

```nginx
upstream strapi_backend {
    server 127.0.0.1:1337 max_fails=3 fail_timeout=30s;          # master (principal)
    server 127.0.0.1:1338 max_fails=3 fail_timeout=30s backup;   # slave (backup)
}
```

- En temps normal : tout le trafic va sur le master (1337)
- Si master est down : nginx bascule automatiquement sur slave (1338) apres 3 echecs
- `proxy_next_upstream error timeout http_502 http_503` : nginx retente sur l'autre serveur en cas d'erreur
- **Pas besoin de `nginx -s reload`** pendant le deploiement. Le failover est automatique.

## Gestion des crons

Strapi execute des taches cron (rappels pre/post pret). Pour eviter les doublons quand les deux instances tournent :

- `strapi-master` : `CRON_ENABLED=true` (execute les crons)
- `strapi-slave` : `CRON_ENABLED=false` (n'execute pas les crons)

C'est configure dans `docker-compose.yml` et lu par `config/server.ts` :

```typescript
cron: {
  enabled: env.bool('CRON_ENABLED', true),
  tasks: cronTasks,
},
```

## Gestion du mot de passe Redis

**Ancien fonctionnement** : Le conteneur Redis generait un mot de passe aleatoire au demarrage et modifiait le fichier `.env` de Strapi via le volume partage.

**Nouveau fonctionnement** : Le mot de passe est defini manuellement dans `docker/.env` (`REDIS_PASSWORD`) et dans `strapi/.env` (`REDIS_PASSWORD`). Le conteneur Redis exige cette variable et refuse de demarrer sans.

Pour generer un mot de passe securise :

```bash
openssl rand -base64 32
```

## Commandes utiles

```bash
# === Services ===
docker compose up -d                                    # Demarrer (master + infra)
docker compose --profile blue-green up -d strapi-slave  # Demarrer le slave
docker compose --profile dev up -d strapi-dev           # Demarrer en mode dev
docker compose down                                     # Arreter tout
docker compose ps                                       # Etat des conteneurs

# === Logs ===
docker compose logs -f strapi-master                    # Logs master
docker compose logs -f strapi-slave                     # Logs slave
docker compose logs -f postgresql                       # Logs PostgreSQL
docker compose logs -f redis                            # Logs Redis

# === Shell ===
docker compose exec strapi-master sh                    # Shell dans master
docker compose exec postgresql psql -U BoB -d BoB      # CLI PostgreSQL
docker compose exec redis redis-cli -a $REDIS_PASSWORD  # CLI Redis

# === Build ===
docker compose build strapi-master                      # Rebuild l'image
docker compose build --no-cache strapi-master            # Rebuild sans cache

# === Deploiement ===
./deploy.sh                                             # Deploiement zero-downtime
./deploy.sh --status                                    # Etat blue-green
./deploy.sh --build-only                                # Build sans deployer
```

## Troubleshooting

### strapi-master ne demarre pas

```bash
# Verifier les logs
docker compose logs strapi-master

# Verifier que l'image a ete buildee
docker images bob-strapi

# Verifier le healthcheck
docker inspect --format='{{.State.Health}}' strapi-master
```

Causes frequentes :
- Le `.env` de Strapi manque des variables (DATABASE_*, REDIS_*, APP_KEYS, etc.)
- L'image n'a pas ete buildee (`docker compose build strapi-master`)
- Le volume d'uploads n'existe pas (`mkdir -p $UPLOADS_VOLUME`)

### Le deploiement echoue a l'etape 3 (slave non healthy)

Le slave n'arrive pas a demarrer. Master n'est pas impacte.

```bash
# Voir les logs du slave
docker compose --profile blue-green logs strapi-slave

# Verifier si c'est un probleme de migration DB
docker compose --profile blue-green logs strapi-slave | grep -i migration
```

### Le deploiement echoue a l'etape 6 (master non healthy apres restart)

Le slave sert le trafic en mode degrade.

```bash
# Voir les logs du master
docker compose logs strapi-master

# Relancer master manuellement
docker compose up -d strapi-master

# Si ca ne marche pas, le slave continue de servir
./deploy.sh --status
```

### Les uploads ne s'affichent pas

Verifier que le volume est correctement monte :

```bash
# Verifier le contenu du volume
ls -la $UPLOADS_VOLUME

# Verifier dans le conteneur
docker compose exec strapi-master ls /app/bob/public/uploads/
```

### PostgreSQL ne demarre pas

```bash
docker compose logs postgresql
ls -la $POSTGRES_VOLUME
```

### Redis refuse de demarrer

Verifier que `REDIS_PASSWORD` est defini dans `docker/.env` :

```bash
grep REDIS_PASSWORD docker/.env
docker compose logs redis
```

### Conflit de port 1337

`strapi-master` et `strapi-dev` utilisent le meme port. Ne pas les lancer en meme temps :

```bash
# Arreter le dev avant de lancer la prod
docker compose --profile dev stop strapi-dev
docker compose up -d strapi-master

# Ou inversement
docker compose stop strapi-master
docker compose --profile dev up -d strapi-dev
```

## Securite

### PostgreSQL
- Authentification SCRAM-SHA-256
- Port non expose a l'exterieur (reseau Docker interne)
- Connexions limitees au reseau `bob-network`

### Redis
- Mot de passe requis (`requirepass`)
- Port non expose a l'exterieur (reseau Docker interne)
- Commandes dangereuses desactivees (`FLUSHDB`, `FLUSHALL`, `CONFIG`)
- Limite memoire : 256 Mo avec politique LRU
- Persistance AOF

### Images Docker Strapi
- Les credentials Firebase et APNs sont COPY dans l'image au build
- **Ne jamais push l'image sur un registry public**
- Amelioration future : monter ces fichiers comme Docker secrets

## Migration depuis l'ancien setup

Si vous migrez depuis le setup avec un seul conteneur `strapi` et volume mount du projet :

### 1. Sauvegarde

```bash
# Backup DB + config
cd docker && ./strapi-data.sh

# Backup uploads
tar -czf uploads-backup-$(date +%Y%m%d).tar.gz -C /chemin/vers/strapi/public uploads

# Backup configs Docker
cp docker-compose.yml docker-compose.yml.backup
cp strapi/Dockerfile strapi/Dockerfile.backup
cp .env .env.backup
```

### 2. Preparer le mot de passe Redis

L'ancien setup generait le mot de passe automatiquement. Recuperez-le et mettez-le dans les `.env` :

```bash
# Lire le mot de passe actuel
docker compose exec redis cat /data/redis_password.txt

# Le mettre dans docker/.env
# REDIS_PASSWORD=<le mot de passe recupere>

# Verifier qu'il est aussi dans strapi/.env
# REDIS_PASSWORD=<le meme mot de passe>
```

### 3. Preparer les uploads

```bash
mkdir -p /chemin/vers/uploads
cp -a /chemin/vers/strapi/public/uploads/* /chemin/vers/uploads/
# Mettre UPLOADS_VOLUME=/chemin/vers/uploads dans docker/.env
```

### 4. Deployer

```bash
# Arreter l'ancien setup
docker compose down

# Build et demarrer le nouveau
docker compose build strapi-master
docker compose up -d

# Verifier
docker compose logs -f strapi-master
curl http://localhost:1337/_health
```

### 5. Installer Nginx

```bash
sudo cp docker/nginx/bob.strapi-pro.com.conf /etc/nginx/conf.d/
sudo nginx -t && sudo nginx -s reload
```

### 6. Verifier

- [ ] `curl http://localhost:1337/_health` retourne 200
- [ ] Admin panel accessible : `http://bob.strapi-pro.com/admin`
- [ ] Les images existantes s'affichent
- [ ] Un nouvel upload fonctionne
- [ ] Les crons tournent (verifier les logs : `[CRON]`)
- [ ] `./deploy.sh --status` affiche master RUNNING + HEALTHY
