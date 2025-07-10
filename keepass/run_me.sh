#!/bin/bash

set -euo pipefail

mkdir -p backup output

# Step 1: export backup from LastPass
read -p "Enter your LastPass username: " LPASS_USERNAME

docker compose run --rm -e LPASS_USERNAME="$LPASS_USERNAME" lastpass-export

echo "\nBackup exported to ./backup.\n"

# Step 2: convert to KeePass
read -p "Enter the name of the KeePass db file (without extension, default: lastpass-export): " KP_DB_NAME
if [[ -z "$KP_DB_NAME" ]]; then
  KP_DB_NAME="lastpass-export"
fi
KP_DB_NAME="${KP_DB_NAME}.kdbx"

docker compose run --rm -e KP_DB_NAME="$KP_DB_NAME" lastpass-processor

echo "\nConversion completed. KeePass file generated in ./output/$KP_DB_NAME\n"
