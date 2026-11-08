#!/bin/sh
#
# Bootstrap packages.alejandro.md on a Debian or Raspbian system.
#
#   curl -fsSL @@BASE_URL@@/setup.sh | sudo sh
#
# This installs the signing key and the APT source, then hands ownership of
# both to the alejandro-md-keyring package so later changes arrive as a normal
# package upgrade rather than another curl-to-shell.

set -e

BASE="@@BASE_URL@@"
BOOTSTRAP_KEY=/usr/share/keyrings/alejandro-md-bootstrap.asc
BOOTSTRAP_SRC=/etc/apt/sources.list.d/alejandro-md-bootstrap.sources

if [ "$(id -u)" -ne 0 ]; then
  echo "This script needs root. Re-run it with sudo." >&2
  exit 1
fi

for tool in curl apt-get dpkg; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

CODENAME=""
if [ -r /etc/os-release ]; then
  CODENAME="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-}")"
fi
if [ -z "$CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
  CODENAME="$(lsb_release -cs 2>/dev/null || true)"
fi

case "$CODENAME" in
  bookworm|trixie)
    SUITE="$CODENAME"
    ;;
  *)
    echo "No packages are built for '${CODENAME:-unknown}'." >&2
    echo "Supported releases: bookworm, trixie." >&2
    exit 1
    ;;
esac

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64|arm64|armhf) ;;
  *)
    echo "No packages are built for architecture '$ARCH'." >&2
    echo "Supported architectures: amd64, arm64, armhf." >&2
    exit 1
    ;;
esac

echo "Fetching the signing key"
install -d -m 0755 /usr/share/keyrings
curl -fsSL "$BASE/gpg.key" -o "$BOOTSTRAP_KEY"
chmod 0644 "$BOOTSTRAP_KEY"

# apt reads an armored key directly when the file is named .asc, so this works
# without pulling in gnupg just to dearmor it.
cat > "$BOOTSTRAP_SRC" <<EOF
Types: deb
URIs: $BASE/deb
Suites: $SUITE
Components: main
Architectures: $ARCH
Signed-By: $BOOTSTRAP_KEY
EOF
chmod 0644 "$BOOTSTRAP_SRC"

echo "Updating package lists"
apt-get update -o Dir::Etc::sourcelist="$BOOTSTRAP_SRC" \
               -o Dir::Etc::sourceparts="-" \
               -o APT::Get::List-Cleanup="0"

echo "Installing alejandro-md-keyring"
apt-get install -y alejandro-md-keyring

# The package now owns the key and the source file.
rm -f "$BOOTSTRAP_SRC" "$BOOTSTRAP_KEY"
apt-get update

echo
echo "Done. $BASE is configured for $SUITE/$ARCH."
echo "Install a package with, for example:"
echo
echo "    sudo apt install mariner3d"
echo
