#!/usr/bin/env bash
#
# Generates an opkg feed index (Packages, Packages.gz) for a directory of
# .ipk files.
#
# The projects that publish .ipk packages today drop them into a directory
# with no index at all, which means `opkg update` against that feed fails.
# opkg's index format is just the concatenated control files with Filename,
# Size and SHA256sum appended, so it is built here rather than pulling in
# OpenWrt's buildroot to run scripts/ipkg-make-index.sh.
#
# usage: mkopkg-index.sh <directory-of-ipk-files>

set -euo pipefail

DIR="${1:?usage: mkopkg-index.sh <directory-of-ipk-files>}"
cd "$DIR"

shopt -s nullglob
ipks=(*.ipk)
if [ ${#ipks[@]} -eq 0 ]; then
  echo "mkopkg-index: no .ipk files in $DIR, nothing to index" >&2
  exit 0
fi

: > Packages

for ipk in "${ipks[@]}"; do
  tmp="$(mktemp -d)"

  # An .ipk is either an ar archive (like a .deb) or a plain tar.gz,
  # depending on which OpenWrt version built it. Try both.
  if ar t "$ipk" >/dev/null 2>&1; then
    ar p "$ipk" control.tar.gz 2>/dev/null | tar -xz -C "$tmp" 2>/dev/null || true
  else
    tar -xzOf "$ipk" ./control.tar.gz 2>/dev/null \
      | tar -xz -C "$tmp" 2>/dev/null || true
    if [ ! -f "$tmp/control" ]; then
      tar -xzOf "$ipk" control.tar.gz 2>/dev/null \
        | tar -xz -C "$tmp" 2>/dev/null || true
    fi
  fi

  ctl="$tmp/control"
  [ -f "$ctl" ] || ctl="$tmp/./control"
  if [ ! -f "$ctl" ]; then
    echo "mkopkg-index: no control file in $ipk, skipping" >&2
    rm -rf "$tmp"
    continue
  fi

  # Control stanza first, with blank lines stripped so the record stays
  # a single paragraph, then the fields opkg needs to fetch and verify.
  sed -e '/^[[:space:]]*$/d' "$ctl" >> Packages
  printf 'Filename: %s\n' "$ipk" >> Packages
  printf 'Size: %s\n' "$(stat -c%s "$ipk")" >> Packages
  printf 'SHA256sum: %s\n' "$(sha256sum "$ipk" | cut -d' ' -f1)" >> Packages
  printf '\n' >> Packages

  rm -rf "$tmp"
done

# -n leaves the timestamp out so an unchanged feed produces an identical
# file and rclone has nothing to re-upload.
gzip -9fkn Packages

echo "mkopkg-index: indexed ${#ipks[@]} package(s) in $DIR"
