#!/bin/bash
# Run this ONLINE (or let the Mirror GitHub Actions workflow run it). Downloads
# Tailscale's Windows MSIs from pkgs.tailscale.com into releases/ so the repo
# can be cloned and installed with install.ps1 / install.cmd on a machine that
# can't reach pkgs.tailscale.com.
#
# Usage: ./mirror.sh [stable|unstable|VERSION] [ARCH ...]
#   ARCH: amd64 arm64 x86 (default: all)
#
# MSIs are ~30MB, under GitHub's 100MB per-file limit, so they're stored whole.

set -e
cd "$(dirname "$0")"

PKGS_BASE_URL="https://pkgs.tailscale.com"
ALL_ARCHES=(amd64 arm64 x86)

TARGET="${1:-stable}"
shift || true
ARCHES=("$@")
if [ ${#ARCHES[@]} -eq 0 ]; then
    ARCHES=("${ALL_ARCHES[@]}")
fi
for arch in "${ARCHES[@]}"; do
    if [[ ! " ${ALL_ARCHES[*]} " =~ " $arch " ]]; then
        echo "Unknown arch: $arch (expected one of: ${ALL_ARCHES[*]})" >&2
        exit 1
    fi
done

for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd is required" >&2; exit 1; }
done

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

if [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    version="$TARGET"
    # Tailscale stable releases have even minor versions, unstable odd.
    minor=$(echo "$version" | cut -d. -f2)
    if [ $((minor % 2)) -eq 0 ]; then track=stable; else track=unstable; fi
elif [ "$TARGET" = "stable" ] || [ "$TARGET" = "unstable" ]; then
    track="$TARGET"
    version=$(curl -fsSL "$PKGS_BASE_URL/$track/?mode=json&os=windows" | jq -r '.MSIsVersion // empty')
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Got an unexpected version from pkgs.tailscale.com: $version" >&2
        exit 1
    fi
else
    echo "Usage: ./mirror.sh [stable|unstable|VERSION] [ARCH ...]" >&2
    exit 1
fi
echo "Mirroring Tailscale $version ($track)"

dest="releases/$version"
mkdir -p "$dest"

for arch in "${ARCHES[@]}"; do
    msi="tailscale-setup-$version-$arch.msi"
    adir="$dest/$arch"
    if [ -f "$adir/$msi" ] && [ -f "$adir/checksum" ] && [ "$(sha256 "$adir/$msi")" = "$(cat "$adir/checksum")" ]; then
        echo "  $arch: already mirrored"
        continue
    fi
    echo "  $arch: downloading"
    rm -rf "$adir"
    mkdir -p "$adir"
    curl -fSL --progress-bar -o "$adir/$msi.tmp" "$PKGS_BASE_URL/$track/$msi"
    checksum=$(sha256 "$adir/$msi.tmp")
    # Cross-check against the published hash when there is one. The real
    # check is the Authenticode signature, which install.ps1 verifies.
    published=$(curl -fsSL "$PKGS_BASE_URL/$track/$msi.sha256" 2>/dev/null | grep -oE '^[a-f0-9]{64}' || true)
    if [ -n "$published" ] && [ "$published" != "$checksum" ]; then
        echo "Checksum verification failed for $arch" >&2
        rm -rf "$adir"
        exit 1
    fi
    mv "$adir/$msi.tmp" "$adir/$msi"
    echo "$checksum" > "$adir/checksum"
done

# The offline installer resolves "stable" and "unstable" from these files.
if [ "$TARGET" = "$track" ] || [ ! -f "releases/$track" ]; then
    echo "$version" > "releases/$track"
fi

echo ""
echo "Done. Commit and push:"
echo "    git add releases && git commit -m \"Mirror Tailscale $version\" && git push"
