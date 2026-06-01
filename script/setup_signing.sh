#!/usr/bin/env bash
set -euo pipefail

# One-time setup so Pastil keeps its Accessibility (auto-paste) permission across rebuilds.
#
# WHY: `build_and_run.sh` re-signs the app every build. With an ad-hoc signature the code
# hash changes each build, which invalidates the Accessibility grant — so auto-paste stops
# working after every rebuild ("permission is on but paste doesn't work"). Signing with a
# STABLE self-signed certificate keeps the same identity across rebuilds, so you grant the
# permission once and it sticks.
#
# This creates a local self-signed code-signing certificate in your login keychain and
# authorizes `codesign` to use it. It does NOT touch the system trust store. Run it once:
#
#     bash script/setup_signing.sh
#
# You may be asked to allow the import / authorize keychain access.

CN="Pastil Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CN"; then
  echo "✓ Signing identity \"$CN\" already exists."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Pastil Local Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "Generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -nodes -config "$WORK/openssl.cnf" >/dev/null 2>&1

# -legacy: macOS `security` can't import OpenSSL 3's default PKCS#12 MAC.
openssl pkcs12 -export -legacy -out "$WORK/id.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:pastil -name "$CN" >/dev/null 2>&1

echo "Importing into login keychain (you may be prompted to allow this)…"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P pastil -A -T /usr/bin/codesign

# A self-signed cert isn't system-"trusted", so it won't appear in `find-identity -v`.
# The real test is whether codesign can actually sign with it.
echo "Verifying the identity can sign…"
PROBE="$WORK/probe"
printf '#!/bin/sh\necho ok\n' > "$PROBE"
chmod +x "$PROBE"
echo
if codesign --force --sign "$CN" "$PROBE" >/dev/null 2>&1; then
  echo "✓ Done — \"$CN\" can sign."
  echo "  1) Rebuild:  bash script/build_and_run.sh"
  echo "  2) Grant Pastil once in System Settings → Privacy & Security → Accessibility."
  echo "  Auto-paste then survives rebuilds."
else
  echo "✗ codesign could not use the certificate. Auto-paste will need re-granting per rebuild."
  exit 1
fi
