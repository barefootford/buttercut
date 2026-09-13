#!/bin/bash
# Installs the pinned ffmpeg/ffprobe builds into dependencies/.
#
# Single source of truth for which FFmpeg customers get: the setup skill,
# the contact-sheet skill's repair path, and CI all run this script. Every
# download is verified against the SHA-256 checksums committed below — a
# mismatch aborts the install rather than ever running an unexpected binary.
#
# Two build sources, one per platform — both compiled with libfreetype +
# libharfbuzz, so the drawtext filter ButterCut needs is always present:
#
#   macOS   https://ffmpeg.martin-riedl.de — static builds, one zip per tool.
#           To bump: pick a build there, update MAC_VERSION and the per-arch
#           BUILD ids, download all four zips, and replace the checksums with
#           your own `shasum -a 256` output (cross-check against the server's
#           published <url>.sha256 files).
#   Windows https://www.gyan.dev/ffmpeg/builds — the "essentials" release
#           build (the same vendor behind winget's Gyan.FFmpeg and Chocolatey's
#           ffmpeg package; one of the two Windows providers ffmpeg.org lists).
#           One zip holds both tools. To bump: pick a versioned package there,
#           update WIN_VERSION, download the zip, and replace the checksum
#           (cross-check against the published <url>.sha256).
set -euo pipefail

cd "$(dirname "$0")/.."

case "$(uname -s)" in
  Darwin)
    OS="macos"
    VERSION="8.1.1"
    EXE=""
    case "$(uname -m)" in
      arm64)
        ARCH="arm64"
        BUILD="1778761665_8.1.1"
        FFMPEG_SHA256="a05b1a47bb3ac89a95a55eec713f8bbb347051bb07015f3b7d08fb62ed81a21e"
        FFPROBE_SHA256="135e70d2518beeb568183952dbc4bdeca1628dd49a7376d57e6b27dbc57d209f"
        ;;
      x86_64)
        ARCH="amd64"
        BUILD="1778768838_8.1.1"
        FFMPEG_SHA256="8cb711bfa6f66033112d708dc275220419d0fdb49c5b752f8db25f11a92d321f"
        FFPROBE_SHA256="e9b9b83fef584c367b27c683a1172921b4f48fa8bd5df6712ef54e63b915ea50"
        ;;
      *)
        echo "install_ffmpeg: unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*)
    OS="windows"
    VERSION="8.1.2"
    EXE=".exe"
    BUNDLE_SHA256="db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec"
    ;;
  *)
    echo "install_ffmpeg: unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac

# Already installed at the pinned version (with drawtext)? Nothing to do —
# keeps setup re-runs fast and makes a pin bump replace old binaries.
# (grep reads its whole input rather than using -q: with pipefail, -q's early
# exit SIGPIPEs ffmpeg and fails the pipeline even on a match.)
if [ -x "dependencies/ffmpeg${EXE}" ] && [ -x "dependencies/ffprobe${EXE}" ] \
  && "dependencies/ffmpeg${EXE}" -version 2>/dev/null | grep "^ffmpeg version ${VERSION}-" > /dev/null \
  && "dependencies/ffprobe${EXE}" -version 2>/dev/null | grep "^ffprobe version ${VERSION}-" > /dev/null \
  && "dependencies/ffmpeg${EXE}" -hide_banner -filters 2>/dev/null | grep ' drawtext ' > /dev/null; then
  echo "ffmpeg + ffprobe ${VERSION} already installed in dependencies/"
  exit 0
fi

mkdir -p dependencies
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_checksum() {
  local file="$1" expected="$2" actual
  actual=$(sha256_of "$file")
  if [ "$actual" != "$expected" ]; then
    echo "install_ffmpeg: SHA-256 mismatch for $(basename "$file") — refusing to install." >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    echo "The download may be corrupted or tampered with. Re-run to retry; if it persists, report it." >&2
    exit 1
  fi
}

if [ "$OS" = "macos" ]; then
  for tool in ffmpeg ffprobe; do
    expected_var="$(printf '%s' "$tool" | tr '[:lower:]' '[:upper:]')_SHA256"
    url="https://ffmpeg.martin-riedl.de/download/macos/${ARCH}/${BUILD}/${tool}.zip"

    echo "Downloading ${tool} ${VERSION} (${ARCH})..."
    curl -fsSL --retry 3 -o "${workdir}/${tool}.zip" "$url"
    verify_checksum "${workdir}/${tool}.zip" "${!expected_var}"

    unzip -o -q -d "${workdir}/${tool}-extract" "${workdir}/${tool}.zip"
    mv "${workdir}/${tool}-extract/${tool}" "dependencies/${tool}"
    chmod +x "dependencies/${tool}"
  done
else
  # Git Bash has no unzip, and its `tar` is GNU tar (no zip support); System32's
  # bsdtar reads zip. Both tools ship in one archive under <build>/bin/.
  bundle="ffmpeg-${VERSION}-essentials_build"
  url="https://www.gyan.dev/ffmpeg/builds/packages/${bundle}.zip"
  win_tar="$(cygpath -u "${SYSTEMROOT:-C:/Windows}")/System32/tar.exe"

  echo "Downloading ffmpeg + ffprobe ${VERSION} (Windows x64)..."
  curl -fsSL --retry 3 -o "${workdir}/${bundle}.zip" "$url"
  verify_checksum "${workdir}/${bundle}.zip" "$BUNDLE_SHA256"

  mkdir -p "${workdir}/extract"
  "$win_tar" -xf "${workdir}/${bundle}.zip" -C "${workdir}/extract"
  for tool in ffmpeg ffprobe; do
    mv "${workdir}/extract/${bundle}/bin/${tool}.exe" "dependencies/${tool}.exe"
  done
fi

"dependencies/ffmpeg${EXE}" -hide_banner -version | head -1
"dependencies/ffprobe${EXE}" -version | head -1
"dependencies/ffmpeg${EXE}" -hide_banner -filters 2>/dev/null | grep ' drawtext ' > /dev/null \
  || { echo "install_ffmpeg: installed ffmpeg has no drawtext filter" >&2; exit 1; }

echo "ffmpeg + ffprobe ${VERSION} installed into dependencies/ (checksums verified)"
