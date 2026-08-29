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
LOCAL_GENERAL_CONFIG="${SCRIPT_ROOT}/config/local/general.h"
LOCAL_CONSOLE_CONFIG="${SCRIPT_ROOT}/config/local/console.h"
EMBED_SCRIPT="${SCRIPT_ROOT}/embed.ipxe"
AUTOEXEC="${SCRIPT_ROOT}/autoexec.ipxe"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || return 1; }
have_lzma_headers() { printf '#include <lzma.h>\n' | gcc -E - >/dev/null 2>&1; }

install_dependencies() {
    local missing=() cmd need_lzma=false
    for cmd in curl tar git make gcc perl getconf; do
        need_cmd "${cmd}" || missing+=("${cmd}")
    done
    if need_cmd gcc && ! have_lzma_headers; then need_lzma=true; fi
    [[ ${#missing[@]} -eq 0 && "${need_lzma}" == false ]] && return 0

    [[ ${#missing[@]} -gt 0 ]] && warn "Missing required commands: ${missing[*]}"
    [[ "${need_lzma}" == true ]] && warn "Missing required iPXE LZMA development headers (lzma.h)."

    if command -v apt-get >/dev/null 2>&1; then
        log "Installing required build dependencies with apt..."
        local sudo_cmd=()
        if [[ ${EUID} -ne 0 ]]; then
            command -v sudo >/dev/null 2>&1 || die "Install: build-essential git curl perl liblzma-dev"
            sudo_cmd=(sudo)
        fi
        "${sudo_cmd[@]}" apt-get update
        "${sudo_cmd[@]}" apt-get install -y build-essential git curl perl liblzma-dev
    else
        die "Install your distribution's compiler/build tools, git, curl, perl and liblzma/xz development headers."
    fi

    for cmd in curl tar git make gcc perl getconf; do
        need_cmd "${cmd}" || die "Required command still unavailable: ${cmd}"
    done
    have_lzma_headers || die "lzma.h is still unavailable."
}

refresh_repo() {
    log "Refreshing repository from origin/main..."
    need_cmd git || die "--refresh requires git."
    git -C "${SCRIPT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "--refresh requires a Git working tree."
    git -C "${SCRIPT_ROOT}" fetch origin main
    git -C "${SCRIPT_ROOT}" reset --hard origin/main
    log "Repository refreshed. Restarting builder..."
    exec bash "${SCRIPT_ROOT}/build.sh"
}

if [[ "${1:-}" == "--refresh" ]]; then refresh_repo
elif [[ $# -gt 0 ]]; then die "Unknown option: $1"
fi

install_dependencies
mkdir -p "${CACHE_DIR}" "${SOURCE_DIR}" "${OUTPUT_DIR}"

printf '\n===============================================================\n'
printf ' iPXE Builder\n Version : %s\n Output  : %s\n' "${IPXE_VERSION}" "${TFTP_DIR}"
printf '===============================================================\n\n'

if [[ ! -s "${UPSTREAM_ARCHIVE}" ]]; then
    log "Downloading official iPXE ${IPXE_VERSION} network boot bundle..."
    curl -fL --retry 3 "${IPXE_RELEASE_BASE}/ipxeboot.tar.gz" -o "${UPSTREAM_ARCHIVE}.tmp"
    mv "${UPSTREAM_ARCHIVE}.tmp" "${UPSTREAM_ARCHIVE}"
else
    log "Using cached official network boot bundle."
fi

rm -rf "${TFTP_DIR}"
mkdir -p "${TFTP_DIR}"
log "Extracting official release files..."
tar -xzf "${UPSTREAM_ARCHIVE}" -C "${TFTP_DIR}"
if [[ -d "${TFTP_DIR}/ipxeboot" ]]; then
    shopt -s dotglob nullglob
    mv "${TFTP_DIR}/ipxeboot/"* "${TFTP_DIR}/"
    shopt -u dotglob nullglob
    rmdir "${TFTP_DIR}/ipxeboot"
fi

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

[[ -f "${LOCAL_GENERAL_CONFIG}" ]] || die "Missing ${LOCAL_GENERAL_CONFIG}"
[[ -f "${LOCAL_CONSOLE_CONFIG}" ]] || die "Missing ${LOCAL_CONSOLE_CONFIG}"
[[ -f "${EMBED_SCRIPT}" ]] || die "Missing ${EMBED_SCRIPT}"

log "Applying local BIOS configuration..."
mkdir -p "${SOURCE_TREE}/src/config/local"
cp "${LOCAL_GENERAL_CONFIG}" "${SOURCE_TREE}/src/config/local/general.h"
cp "${LOCAL_CONSOLE_CONFIG}" "${SOURCE_TREE}/src/config/local/console.h"

# Legacy BIOS starts from the machine's existing PXE/UNDI stack.  Embed only a
# tiny bootstrap that explicitly loads /autoexec.ipxe from the TFTP server.
# This prevents DHCP from handing iPXE its own filename again and causing a
# chainload loop, while keeping the real autoexec.ipxe editable on the server.
log "Building legacy BIOS UNDI chainloader with embedded TFTP bootstrap..."
make -C "${SOURCE_TREE}/src" \
    -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)" \
    bin/undionly.kpxe \
    EMBED="${EMBED_SCRIPT}"

[[ -s "${SOURCE_TREE}/src/bin/undionly.kpxe" ]] || die "BIOS build did not produce bin/undionly.kpxe"

mkdir -p "${TFTP_DIR}/non-efi"
cp "${SOURCE_TREE}/src/bin/undionly.kpxe" "${TFTP_DIR}/non-efi/ipxe.pxe"

# This is the external, editable second-stage script expected by embed.ipxe.
if [[ -f "${AUTOEXEC}" ]]; then
    cp "${AUTOEXEC}" "${TFTP_DIR}/autoexec.ipxe"
fi

cat > "${TFTP_DIR}/BUILD-INFO.txt" <<EOF
ipxe-builder
============
Builder repository : https://github.com/theretrobristolian/ipxe-builder
iPXE release       : ${IPXE_VERSION}
iPXE source tag    : ${IPXE_TAG}

UEFI/Secure Boot:
  Official upstream iPXE ${IPXE_VERSION} release files.

Legacy BIOS:
  non-efi/ipxe.pxe is a locally compiled bin/undionly.kpxe, renamed to retain
  the existing DHCP filename.

  The binary embeds only embed.ipxe.  That bootstrap obtains DHCP and chains
  explicitly to tftp://\${next-server}/autoexec.ipxe.  The real autoexec.ipxe
  therefore remains an external editable TFTP file and does not require the
  BIOS binary to be rebuilt when menu/bootstrap settings change.

  Local BIOS features include console command, PNG image support and the
  framebuffer console.
EOF

printf '\n'
log "Build complete."
printf '\nTFTP root:\n  %s\n\n' "${TFTP_DIR}"
printf 'Legacy BIOS test file:\n  non-efi/ipxe.pxe\n'
printf 'External editable script:\n  autoexec.ipxe\n\n'
