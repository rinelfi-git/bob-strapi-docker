#!/bin/bash
set -euo pipefail

# =============================================================================
# Script de deploiement Blue-Green pour Bob Strapi
#
# Nginx tourne dans un conteneur Docker et route le trafic via :
#   - strapi-master (port 1337 interne) = serveur principal
#   - strapi-slave  (port 1337 interne) = serveur fallback (via error_page)
# Le failover est automatique via error_page 502/503/504 -> @slave_fallback.
# Les noms de conteneurs sont resolus dynamiquement (resolver Docker 127.0.0.11).
#
# Workflow de deploiement :
#   1. Build la nouvelle image
#   2. Demarrer slave avec la nouvelle image
#   3. Attendre que slave soit healthy
#   4. Stopper master -> nginx bascule auto sur slave (error_page fallback)
#   5. Redemarrer master avec la nouvelle image
#   6. Attendre que master soit healthy -> nginx remet master en principal
#   7. Stopper slave
#
# Usage:
#   ./deploy.sh                    # Deploiement complet (zero-downtime)
#   ./deploy.sh --status           # Afficher l'etat des conteneurs
#   ./deploy.sh --build-only       # Build l'image sans deployer
#   ./deploy.sh --help             # Afficher l'aide
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Fonctions utilitaires
# =============================================================================

# Verifier si un conteneur est running
is_running() {
    local container=$1
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
    [ "$status" = "running" ]
}

# Verifier si un conteneur est healthy
is_healthy() {
    local container=$1
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
    [ "$status" = "healthy" ]
}

# Attendre qu'un conteneur soit healthy
wait_for_healthy() {
    local container=$1
    local max_wait=${2:-180}
    local elapsed=0

    log_info "En attente du healthcheck de $container (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")

        if [ "$status" = "healthy" ]; then
            printf "\r\033[K"
            log_success "$container est healthy ! (en ${elapsed}s)"
            return 0
        fi

        local remaining=$((max_wait - elapsed))
        local mins=$((remaining / 60))
        local secs=$((remaining % 60))

        local display_status
        if [ "$status" = "not_found" ]; then
            display_status="en attente du conteneur"
        else
            display_status="$status"
        fi

        echo -ne "\r\033[K  $container : $display_status -- temps restant : $(printf '%02d:%02d' "$mins" "$secs")"

        sleep 1
        elapsed=$((elapsed + 1))
    done

    printf "\r\033[K"
    log_error "$container n'est pas devenu healthy en ${max_wait}s"
    return 1
}

# Afficher le statut actuel
show_status() {
    echo ""
    log_info "=== Statut Blue-Green ==="
    echo ""

    # Master
    if is_running "bstrapi-master"; then
        if is_healthy "bstrapi-master"; then
            log_success "strapi-master : RUNNING + HEALTHY"
        else
            log_warning "strapi-master : RUNNING (not healthy yet)"
        fi
    else
        log_info "strapi-master : STOPPED"
    fi

    # Slave
    if is_running "bstrapi-slave"; then
        if is_healthy "bstrapi-slave"; then
            log_success "strapi-slave  : RUNNING + HEALTHY"
        else
            log_warning "strapi-slave  : RUNNING (not healthy yet)"
        fi
    else
        log_info "strapi-slave  : STOPPED"
    fi

    # Nginx
    if is_running "bnginx"; then
        log_success "nginx         : RUNNING"
    else
        log_warning "nginx         : STOPPED"
    fi

    echo ""
    log_info "Nginx (conteneur bob-nginx) : master = principal, slave = fallback"
    log_info "Le failover est automatique via error_page si le principal est down."
    echo ""

    log_info "Tous les conteneurs :"
    docker compose -f "$COMPOSE_FILE" --profile blue-green ps 2>/dev/null || true
    echo ""
}

# =============================================================================
# Version management
# =============================================================================

# Valider le format semver (x.y.z)
validate_version() {
    local version=$1
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Format de version invalide: '$version' (attendu: x.y.z)"
        exit 1
    fi
}

# Mettre a jour STRAPI_VERSION dans .env
update_env_version() {
    local version=$1
    local env_file="$SCRIPT_DIR/.env"

    if [ ! -f "$env_file" ]; then
        log_error "Fichier .env introuvable: $env_file"
        exit 1
    fi

    local old_version
    old_version=$(grep -oP '^STRAPI_VERSION=\K.*' "$env_file" 2>/dev/null || echo "unknown")

    sed -i "s/^STRAPI_VERSION=.*/STRAPI_VERSION=$version/" "$env_file"

    log_success "STRAPI_VERSION mis a jour dans .env: $old_version -> $version"
}

# =============================================================================
# Build
# =============================================================================
build_image() {
    local version=${1:-$(date +%Y%m%d%H%M%S)}

    log_info "Build de l'image Strapi avec tag : bob-strapi:$version"

    docker compose -f "$COMPOSE_FILE" build strapi-master > /dev/null 2>&1

    log_success "Image buildee : bob-strapi:$version"
}

# =============================================================================
# Deploiement principal (zero-downtime)
#
# Le principe : nginx route vers master en principal. Si master est down,
# error_page redirige vers @slave_fallback (resolution dynamique).
# =============================================================================
deploy() {
    local target_version="${1:-}"

    echo ""
    log_info "========================================="
    log_info "  Deploiement Blue-Green (zero-downtime)"
    log_info "========================================="
    echo ""

    # Si une version est specifiee, mettre a jour .env avant le build
    if [ -n "$target_version" ]; then
        validate_version "$target_version"
        log_info "Version cible : $target_version"
        update_env_version "$target_version"
        echo ""
    fi

    # Lire la version depuis .env (mise a jour ou existante)
    local version
    version=$(grep -oP '^STRAPI_VERSION=\K.*' "$SCRIPT_DIR/.env" 2>/dev/null || echo "unknown")

    # Etape 1 : Build (utilise STRAPI_VERSION du .env pour le tag de l'image)
    log_info "Etape 1/7 : Build de la nouvelle image..."
    build_image "$version"
    echo ""

    # Etape 2 : Demarrer slave avec la nouvelle image
    log_info "Etape 2/7 : Demarrage de strapi-slave avec la nouvelle image..."
    docker compose -f "$COMPOSE_FILE" --profile blue-green stop strapi-slave 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" --profile blue-green rm -f strapi-slave 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" --profile blue-green up -d strapi-slave
    echo ""

    # Etape 3 : Attendre que slave soit healthy
    log_info "Etape 3/7 : Attente du healthcheck de strapi-slave..."
    if ! wait_for_healthy "bstrapi-slave" 300; then
        log_error "strapi-slave n'a pas demarre correctement. Deploiement annule."
        log_warning "strapi-master continue de servir le trafic (inchange)."
        echo ""
        log_info "Logs de strapi-slave :"
        docker compose -f "$COMPOSE_FILE" --profile blue-green logs --tail=50 strapi-slave
        # Arreter le slave defaillant
        docker compose -f "$COMPOSE_FILE" --profile blue-green stop strapi-slave 2>/dev/null || true
        exit 1
    fi
    echo ""

    # Etape 4 : Stopper master -> nginx bascule automatiquement sur slave (error_page fallback)
    log_info "Etape 4/7 : Arret de strapi-master (nginx bascule auto sur slave)..."
    docker compose -f "$COMPOSE_FILE" stop strapi-master
    docker compose -f "$COMPOSE_FILE" rm -f strapi-master
    log_success "strapi-master arrete. Le trafic est sur strapi-slave."
    echo ""

    # Etape 5 : Redemarrer master avec la nouvelle image
    log_info "Etape 5/7 : Redemarrage de strapi-master avec la nouvelle image..."
    docker compose -f "$COMPOSE_FILE" up -d strapi-master
    echo ""

    # Etape 6 : Attendre que master soit healthy
    log_info "Etape 6/7 : Attente du healthcheck de strapi-master..."
    if ! wait_for_healthy "bstrapi-master" 180; then
        log_error "strapi-master n'a pas redemarre correctement."
        log_warning "strapi-slave continue de servir le trafic (failover actif)."
        log_warning "Investiguer les logs, puis relancer manuellement."
        echo ""
        log_info "Logs de strapi-master :"
        docker compose -f "$COMPOSE_FILE" logs --tail=50 strapi-master
        exit 1
    fi
    echo ""

    # Etape 7 : Stopper slave (master reprend le role principal)
    log_info "Etape 7/7 : Arret de strapi-slave (master reprend le trafic)..."
    docker compose -f "$COMPOSE_FILE" --profile blue-green stop strapi-slave 2>/dev/null || true
    log_success "strapi-slave arrete. strapi-master sert le trafic."
    echo ""

    log_success "========================================="
    log_success "  Deploiement termine avec succes !"
    log_success "========================================="
    log_info "strapi-master tourne avec la nouvelle image (bob-strapi:$version)"
    log_info "strapi-slave est arrete."
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================
case "${1:-}" in
    --version)
        if [ -z "${2:-}" ]; then
            log_error "Version manquante. Usage: $0 --version x.y.z"
            exit 1
        fi
        deploy "$2"
        ;;
    --status)
        show_status
        ;;
    --build-only)
        build_image "${2:-}"
        ;;
    --help|-h)
        echo ""
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  (sans args)            Deploiement complet zero-downtime"
        echo "  --version x.y.z        Deployer avec une nouvelle version (met a jour .env et l'image)"
        echo "  --status               Afficher l'etat des conteneurs"
        echo "  --build-only [tag]     Build l'image sans deployer"
        echo "  --help                 Afficher cette aide"
        echo ""
        echo "Exemples:"
        echo "  $0                     # Deploy avec la version actuelle du .env"
        echo "  $0 --version 2.1.0     # Met a jour STRAPI_VERSION=2.1.0 dans .env, rebuild et deploy"
        echo ""
        echo "Workflow de deploiement :"
        echo "  1. Build nouvelle image"
        echo "  2. Demarrer slave (backup) avec nouvelle image"
        echo "  3. Attendre que slave soit healthy"
        echo "  4. Stopper master -> nginx bascule auto sur slave"
        echo "  5. Redemarrer master avec nouvelle image"
        echo "  6. Attendre que master soit healthy"
        echo "  7. Stopper slave -> master reprend le trafic"
        echo ""
        echo "En cas d'echec a l'etape 3 : master est inchange, rien ne casse"
        echo "En cas d'echec a l'etape 6 : slave sert le trafic, intervenir manuellement"
        echo ""
        ;;
    "")
        deploy
        ;;
    *)
        log_error "Option inconnue: $1"
        echo "Usage: $0 [--version x.y.z|--status|--build-only|--help]"
        exit 1
        ;;
esac
