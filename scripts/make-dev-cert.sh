#!/bin/bash
# Creates a self-signed code-signing certificate "Podium Dev" in the login keychain.
# A stable identity keeps the Accessibility (TCC) grant valid across rebuilds.
# Run once; may prompt for the keychain password.
set -euo pipefail

NAME="Podium Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "'$NAME' signing identity already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.conf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/podium.p12" -passout pass:podium -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/podium.p12" -passout pass:podium

security import "$TMP/podium.p12" -k "$KEYCHAIN" -P podium -T /usr/bin/codesign
echo "Created '$NAME'. Verify with: security find-identity -p codesigning"
