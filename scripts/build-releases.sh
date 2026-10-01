#!/usr/bin/env bash
# =====================================================================
# Tilly - Orchestration des builds sur le VPS
# =====================================================================
# Usage:
#   build-releases.sh <repo_url> <tag> <version>
#
# Exemple:
#   /opt/build-releases.sh \
#     "https://github.com/<owner>/tilly-app.git" \
#     "v1.2.3" \
#     "1.2.3"
#
# Attendu sur le VPS:
#   - Docker + buildx installes
#   - Secrets dans /opt/tilly-secrets/
#       key.properties, tilly-release.jks, google-services.json
#   - Dossier de sortie /opt/releases/
# =====================================================================

set -euo pipefail

REPO_URL="${1:?repo_url requis}"
TAG="${2:?tag requis}"
VERSION="${3:?version requis}"

BUILD_DIR="$(mktemp -d /tmp/tilly-build-XXXXXX)"
RELEASE_DIR="/opt/releases/${VERSION}"
SECRETS_DIR="/opt/tilly-secrets"
ARTIFACT_DIR="${BUILD_DIR}/out"

cleanup() {
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

log() { echo "[build-releases] $*"; }

# ---------------------------------------------------------------------
# 1. Gestion hotfix : un hotfix remplace la derniere version stable
# ---------------------------------------------------------------------
if [[ "${VERSION}" == *-hotfix* ]]; then
    LAST_STABLE="$(ls -1 /opt/releases/ 2>/dev/null | grep -v -- '-hotfix' | sort -V | tail -n 1 || true)"
    if [[ -n "${LAST_STABLE}" ]]; then
        log "Hotfix detecte : suppression de la version ${LAST_STABLE}"
        rm -rf "/opt/releases/${LAST_STABLE}"
    fi
fi

# ---------------------------------------------------------------------
# 2. Clone du depot a la bonne reference
# ---------------------------------------------------------------------
log "Clone ${REPO_URL} @ ${TAG}"
git clone --depth 1 --branch "${TAG}" "${REPO_URL}" "${BUILD_DIR}/src"
cd "${BUILD_DIR}/src"

# ---------------------------------------------------------------------
# 3. Injection des secrets de signature
# ---------------------------------------------------------------------
if [[ ! -d "${SECRETS_DIR}" ]]; then
    log "ERREUR: dossier de secrets absent (${SECRETS_DIR})"
    exit 1
fi

install -m 600 "${SECRETS_DIR}/key.properties" "android/key.properties"
install -m 600 "${SECRETS_DIR}/tilly-release.jks" "android/app/tilly-release.jks"
install -m 600 "${SECRETS_DIR}/google-services.json" "android/app/google-services.json"

# ---------------------------------------------------------------------
# 4. Calcul du build_number (identique au workflow GitHub)
# ---------------------------------------------------------------------
clean_version="${VERSION%%-*}"
IFS='.' read -r major minor patch <<< "${clean_version}"
major="${major:-0}"; minor="${minor:-0}"; patch="${patch:-0}"
build_number=$((10#${major} * 1000000 + 10#${minor} * 1000 + 10#${patch}))
[[ ${build_number} -lt 2 ]] && build_number=2
log "Version ${VERSION} -> build_number ${build_number}"

# ---------------------------------------------------------------------
# 5. Build Docker (export des artefacts via BuildKit)
# ---------------------------------------------------------------------
log "Build Android via Docker..."
mkdir -p "${ARTIFACT_DIR}"
docker build \
    --build-arg APP_VERSION="${VERSION}" \
    --build-arg BUILD_NUMBER="${build_number}" \
    --target artifacts \
    --output "type=local,dest=${ARTIFACT_DIR}" \
    .

if [[ -z "$(ls -A "${ARTIFACT_DIR}" 2>/dev/null)" ]]; then
    log "ERREUR: aucun artefact produit"
    exit 1
fi

# ---------------------------------------------------------------------
# 6. Publication dans /opt/releases/<version>
# ---------------------------------------------------------------------
log "Publication dans ${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"
cp -a "${ARTIFACT_DIR}"/. "${RELEASE_DIR}/"

# ---------------------------------------------------------------------
# 7. Manifest pour le marketplace
# ---------------------------------------------------------------------
FILES_JSON="$(cd "${RELEASE_DIR}" && ls -1 | grep -v manifest.json | jq -R -s 'split("\n") | map(select(length > 0))')"

cat > "${RELEASE_DIR}/manifest.json" <<EOF
{
  "version": "${VERSION}",
  "tag": "${TAG}",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "files": ${FILES_JSON}
}
EOF

log "Termine. Artefacts:"
ls -la "${RELEASE_DIR}"
