#!/usr/bin/env bash
#
# Builds the alejandro-md-keyring package: the one-time bootstrap that installs
# the signing key and registers the APT source for packages.alejandro.md.
# Every other package in this repository depends on it, so a user who installs
# any of them ends up with exactly one source line and one keyring.
#
# usage: build.sh <version> <armored-public-key> <output-dir>

set -euo pipefail

VERSION="${1:?usage: build.sh <version> <armored-public-key> <output-dir>}"
KEYFILE="${2:?missing armored public key}"
OUTDIR="${3:?missing output directory}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

install -d -m 0755 "$WORK/DEBIAN"
install -d -m 0755 "$WORK/usr/share/keyrings"

gpg --dearmor < "$KEYFILE" > "$WORK/usr/share/keyrings/alejandro-md.gpg"
chmod 0644 "$WORK/usr/share/keyrings/alejandro-md.gpg"

cat > "$WORK/DEBIAN/control" <<EOF
Package: alejandro-md-keyring
Version: $VERSION
Architecture: all
Maintainer: Alejandro Mora <mail@alejandro.md>
Section: misc
Priority: optional
Depends: ca-certificates
Homepage: https://packages.alejandro.md
Description: GPG keyring and APT source for packages.alejandro.md
 Installs the OpenPGP public key used to sign every package published at
 packages.alejandro.md, and registers the matching APT source for the
 running Debian or Raspbian release.
 .
 Packages from that repository depend on this one, so the source and key
 are configured once rather than duplicated per project.
EOF

install -m 0755 "$(dirname "$0")/postinst" "$WORK/DEBIAN/postinst"
install -m 0755 "$(dirname "$0")/postrm"   "$WORK/DEBIAN/postrm"

mkdir -p "$OUTDIR"
dpkg-deb --root-owner-group --build "$WORK" \
  "$OUTDIR/alejandro-md-keyring_${VERSION}_all.deb"

echo "built $OUTDIR/alejandro-md-keyring_${VERSION}_all.deb"
