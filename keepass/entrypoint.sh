#!/bin/bash
set -euo pipefail

# Prende il primo parametro come username LastPass, se non presente lo chiede
if [ $# -ge 1 ]; then
  LPASS_USERNAME="$1"
  shift
else
  read -p "Enter your LastPass email: " LPASS_USERNAME
fi

lpass login "$LPASS_USERNAME"

# Se non viene passato un path di destinazione, usa /backup di default
DEST_DIR="${1:-/backup}"

lpass-att-export.sh -l "$LPASS_USERNAME" -o "$DEST_DIR"
