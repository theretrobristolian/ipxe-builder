#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# iPXE Builder
# The Retro Bristolian
# https://github.com/theretrobristolian/ipxe-builder
# ==============================================================================

IPXE_VERSION="2.0.0"
IPXE_TAG="v${IPXE_VERSION}"
IPXE_RELEASE_BASE="https://github.com/ipxe/ipxe/releases/download/${IPXE_TAG}"
IPXE_REPO="https://github.com/ipxe/ipxe.git"

SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_ROOT}/cache"
SOURCE_DIR="${SCRIPT_ROOT}/source"
OUTPUT_DIR="${SCRIPT_ROOT}/output"
TFTP_DIR="${OUTPUT_DIR}/TFTP"
UPSTREAM_ARCHIVE="${CACHE_DIR}/ipxeboot-${IPXE_VERSION}.tar.gz"
SOURCE_TREE="${SOURCE_DIR}/ipxe-${IPXE_VERSION}"
LOCAL_CONFIG="${SCRIPT_ROOT}/config/local/general.h"
AUTOEXEC="${SCRIPT_ROOT}/autoexec.ipxe"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || return 1
}

have_lzma_headers() {
    printf '#include <lzma.h>\n' | gcc -E - >/dev/null 2>&1
}

install_dependencies() {
    local missing=()
    local cmd
    local need_lzma=false

    for cmd in curl tar git make gcc perl getconf; do
        need_cmd "${cmd}" || missing+=("${cmd}")
    done

    if need_cmd gcc && ! have_lzma_headers; then
        need_lzma=true
    fi

    [[ ${#missing[@]} -eq 0 && "${need_lzma}" == false ]] && return 0

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing required commands: ${missing[*]}"
    fi

    if [[ "${need_lzma}" == true ]]; then
        warn "Missing required iPXE LZMA development headers (lzma.h)."
    fi

    if command -v apt-get >/dev/null 2>&1; then
        log "Installing required build dependencies with apt..."

        local sudo_cmd=()
        if [[ ${EUID} -ne 0 ]]; then
            command -v sudo >/dev/null 2>&1 || \
                die "Dependencies are missing and sudo is not available. Install: build-essential git curl perl liblzma-dev"
            sudo_cmd=(sudo)
        fi

        "${sudo_cmd[@]}" apt-get update
        "${sudo_cmd[@]}" apt-get install -y build-essential git curl perl liblzma-dev
    else
        die "Missing iPXE build dependencies. Install your distribution's build-essential/compiler, git, curl, perl and liblzma/xz development headers, then rerun build.sh."
    fi

    for cmd in curl tar git make gcc perl getconf; do
        need_cmd "${cmd}" || die "Required command still unavailable after dependency installation: ${cmd}"
    done

    have_lzma_headers || die "lzma.h is still unavailable after dependency installation."
}

refresh_repo() {
    log "Refreshing repository from origin/main..."

    need_cmd git || die "--refresh requires git to be installed."

    git -C "${SCRIPT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
        die "--refresh requires this project to be a Git working tree."

    git -C "${SCRIPT_ROOT}" fetch origin main
    git -C "${SCRIPT_ROOT}" reset --hard origin/main

    log "Repository refreshed. Restarting builder..."
    exec bash "${SCRIPT_ROOT}/build.sh"
}

if [[ "${1:-}" == "--refresh" ]]; then
    refresh_repo
elif [[ $# -gt 0 ]]; then
    die "Unknown option: $1"
fi

install_dependencies

mkdir -p "${CACHE_DIR}" "${SOURCE_DIR}" "${OUTPUT_DIR}"

printf '\n'
printf '===============================================================\n'
printf ' iPXE Builder\n'
printf ' Version : %s\n' "${IPXE_VERSION}"
printf ' Output  : %s\n' "${TFTP_DIR}"
printf '===============================================================\n\n'

# ------------------------------------------------------------------------------
# Official network-boot release bundle
# ------------------------------------------------------------------------------
if [[ ! -s "${UPSTREAM_ARCHIVE}" ]]; then
    log "Downloading official iPXE ${IPXE_VERSION} network boot bundle..."
    curl -fL --retry 3 \
        "${IPXE_RELEASE_BASE}/ipxeboot.tar.gz" \
        -o "${UPSTREAM_ARCHIVE}.tmp"
    mv "${UPSTREAM_ARCHIVE}.tmp" "${UPSTREAM_ARCHIVE}"
else
    log "Using cached official network boot bundle."
fi

rm -rf "${TFTP_DIR}"
mkdir -p "${TFTP_DIR}"

log "Extracting official release files..."
tar -xzf "${UPSTREAM_ARCHIVE}" -C "${TFTP_DIR}"

# The release archive may contain a single ipxeboot/ top-level directory.
# Flatten that directory so output/TFTP is itself the TFTP root.
if [[ -d "${TFTP_DIR}/ipxeboot" ]]; then
    shopt -s dotglob nullglob
    mv "${TFTP_DIR}/ipxeboot/"* "${TFTP_DIR}/"
    shopt -u dotglob nullglob
    rmdir "${TFTP_DIR}/ipxeboot"
fi

# ------------------------------------------------------------------------------
# Matching source tree for the locally built legacy BIOS image
# ------------------------------------------------------------------------------
if [[ ! -d "${SOURCE_TREE}/.git" ]]; then
    log "Cloning iPXE source ${IPXE_TAG}..."
    rm -rf "${SOURCE_TREE}"
    git clone --depth 1 --branch "${IPXE_TAG}" "${IPXE_REPO}" "${SOURCE_TREE}"
else
    log "Using cached iPXE source tree."
    git -C "${SOURCE_TREE}" fetch --depth 1 origin "refs/tags/${IPXE_TAG}:refs/tags/${IPXE_TAG}" || true
    git -C "${SOURCE_TREE}" reset --hard "${IPXE_TAG}"
    git -C "${SOURCE_TREE}" clean -fdx
fi

[[ -f "${LOCAL_CONFIG}" ]] || die "Missing local configuration: ${LOCAL_CONFIG}"

log "Applying local BIOS build configuration..."
mkdir -p "${SOURCE_TREE}/src/config/local"
cp "${LOCAL_CONFIG}" "${SOURCE_TREE}/src/config/local/general.h"

log "Building legacy BIOS ipxe.pxe..."
make -C "${SOURCE_TREE}/src" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" bin/ipxe.pxe

[[ -s "${SOURCE_TREE}/src/bin/ipxe.pxe" ]] || die "BIOS build did not produce bin/ipxe.pxe"

mkdir -p "${TFTP_DIR}/non-efi"
cp "${SOURCE_TREE}/src/bin/ipxe.pxe" "${TFTP_DIR}/non-efi/ipxe.pxe"

# iPXE 2.0.0 automatically attempts autoexec.ipxe when present.
if [[ -f "${AUTOEXEC}" ]]; then
    cp "${AUTOEXEC}" "${TFTP_DIR}/autoexec.ipxe"
fi

# Record exactly what created this output tree.
cat > "${TFTP_DIR}/BUILD-INFO.txt" <<EOF
ipxe-builder
============
Builder repository : https://github.com/theretrobristolian/ipxe-builder
iPXE release       : ${IPXE_VERSION}
iPXE source tag    : ${IPXE_TAG}

UEFI/Secure Boot files:
  Official upstream files from the iPXE ${IPXE_VERSION} ipxeboot.tar.gz release.

Legacy BIOS:
  non-efi/ipxe.pxe is locally compiled from the matching ${IPXE_TAG} source tag
  using config/local/general.h from this repository.
EOF

printf '\n'
log "Build complete."
printf '\nTFTP root:\n  %s\n\n' "${TFTP_DIR}"
printf 'Suggested starting points:\n'
printf '  Legacy BIOS      : non-efi/ipxe.pxe\n'
printf '  x86-64 SecureBoot: x86_64-sb/shimx64.efi\n'
printf '\nInspect output/TFTP for the complete upstream architecture set.\n'
