#!/bin/sh
#
# Bootstrap packages.alejandro.md.
#
#   Debian / Raspbian   curl -fsSL @@BASE_URL@@/setup.sh | sudo sh
#   Fedora / EL         curl -fsSL @@BASE_URL@@/setup.sh | sudo sh
#   FreeBSD             fetch -qo - @@BASE_URL@@/setup.sh | sh
#   OpenWrt             wget -qO - @@BASE_URL@@/setup.sh | sh
#
# One script, one URL, four package managers. On apt and dnf it installs a
# small release package that then owns the source definition, so later
# changes arrive as a normal upgrade rather than another curl into a shell.

set -e

BASE="@@BASE_URL@@"

die() { echo "$*" >&2; exit 1; }

fetch_to() {
  # $1 url, $2 destination
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v fetch >/dev/null 2>&1; then
    fetch -qo "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    die "Need one of curl, fetch or wget."
  fi
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "This script needs root. Re-run it with sudo."
  fi
}

# ---------------------------------------------------------------- Debian

setup_apt() {
  require_root

  CODENAME=""
  if [ -r /etc/os-release ]; then
    CODENAME="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-}")"
  fi
  if [ -z "$CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
    CODENAME="$(lsb_release -cs 2>/dev/null || true)"
  fi

  case "$CODENAME" in
    bookworm|trixie) SUITE="$CODENAME" ;;
    *) die "No packages are built for '${CODENAME:-unknown}'. Supported: bookworm, trixie." ;;
  esac

  ARCH="$(dpkg --print-architecture)"
  case "$ARCH" in
    amd64|arm64|armhf|armel) ;;
    *) die "No packages are built for architecture '$ARCH'." ;;
  esac

  BOOT_KEY=/usr/share/keyrings/alejandro-md-bootstrap.asc
  BOOT_SRC=/etc/apt/sources.list.d/alejandro-md-bootstrap.sources

  echo "Fetching the signing key"
  mkdir -p /usr/share/keyrings
  fetch_to "$BASE/gpg.key" "$BOOT_KEY"
  chmod 0644 "$BOOT_KEY"

  # apt reads an armored key directly when the file is named .asc, so this
  # needs no gnupg just to dearmor it.
  cat > "$BOOT_SRC" <<EOF
Types: deb
URIs: $BASE/deb
Suites: $SUITE
Components: main
Architectures: $ARCH
Signed-By: $BOOT_KEY
EOF
  chmod 0644 "$BOOT_SRC"

  echo "Updating package lists"
  apt-get update -o Dir::Etc::sourcelist="$BOOT_SRC" \
                 -o Dir::Etc::sourceparts="-" \
                 -o APT::Get::List-Cleanup="0"

  echo "Installing alejandro-md-keyring"
  apt-get install -y alejandro-md-keyring

  # The package now owns the key and the source file.
  rm -f "$BOOT_SRC" "$BOOT_KEY"
  apt-get update

  echo
  echo "Done. $BASE is configured for $SUITE/$ARCH."
  echo "    sudo apt install mariner3d"
}

# ------------------------------------------------------------------- RPM

setup_rpm() {
  require_root

  if command -v dnf >/dev/null 2>&1; then
    PM=dnf
  else
    PM=yum
  fi

  echo "Importing the signing key"
  TMPKEY="$(mktemp)"
  fetch_to "$BASE/gpg.key" "$TMPKEY"
  rpm --import "$TMPKEY"
  rm -f "$TMPKEY"

  # A minimal definition, just enough to install the release package that
  # then replaces it with its own managed copy.
  cat > /etc/yum.repos.d/alejandro-md-bootstrap.repo <<EOF
[alejandro-md-bootstrap]
name=Alejandro Mora Packages (bootstrap)
baseurl=$BASE/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$BASE/gpg.key
EOF

  echo "Installing alejandro-md-release"
  $PM -y install alejandro-md-release

  rm -f /etc/yum.repos.d/alejandro-md-bootstrap.repo
  $PM -q makecache >/dev/null 2>&1 || true

  echo
  echo "Done. $BASE is configured."
  echo "    sudo $PM install unifi-gateway"
}

# --------------------------------------------------------------- FreeBSD

setup_pkg() {
  require_root

  mkdir -p /usr/local/etc/pkg/repos
  cat > /usr/local/etc/pkg/repos/alejandro-md.conf <<EOF
alejandro-md: {
  url: "$BASE/pkg",
  enabled: yes,
  signature_type: "none"
}
EOF

  echo "Updating the package catalogue"
  pkg update

  echo
  echo "Done. $BASE is configured."
  echo "    pkg install unifi-gateway"
  echo
  echo "Note: this repository is unsigned for FreeBSD. pkg cannot verify it"
  echo "with the OpenPGP key used for the deb and rpm channels."
}

# --------------------------------------------------------------- OpenWrt

setup_openwrt() {
  require_root

  if command -v apk >/dev/null 2>&1; then
    LINE="$BASE/openwrt/apk"
    if ! grep -qF "$LINE" /etc/apk/repositories 2>/dev/null; then
      echo "$LINE" >> /etc/apk/repositories
    fi
    apk update --allow-untrusted || apk update
    echo
    echo "Done. Run: apk add --allow-untrusted unifi-gateway"
  else
    FEED="src/gz alejandro-md $BASE/openwrt/ipk"
    if ! grep -qF "alejandro-md" /etc/opkg/customfeeds.conf 2>/dev/null; then
      echo "$FEED" >> /etc/opkg/customfeeds.conf
    fi
    opkg update
    echo
    echo "Done. Run: opkg install unifi-gateway"
  fi

  echo
  echo "Note: this feed is unsigned. OpenWrt verifies feeds with usign keys,"
  echo "not the OpenPGP key used for the deb and rpm channels, so installs"
  echo "may need --allow-untrusted (apk) or --nogpgcheck (opkg)."
}

# -------------------------------------------------------------- dispatch

if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
  setup_apt
elif command -v rpm >/dev/null 2>&1; then
  setup_rpm
elif command -v pkg >/dev/null 2>&1 && [ "$(uname -s)" = "FreeBSD" ]; then
  setup_pkg
elif command -v opkg >/dev/null 2>&1 || command -v apk >/dev/null 2>&1; then
  setup_openwrt
else
  die "No supported package manager found (apt, dnf/yum, pkg, opkg, apk)."
fi
