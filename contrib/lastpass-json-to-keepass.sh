#!/bin/bash
# Converts LastPass JSON export + attachments to a KeePassXC database
# Requirements: keepassxc-cli, jq

# Logging configuration
LOG_PREFIX="import-keepass"
LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_DIR="logs"

# Create logs directory if not exists
mkdir -p "$LOG_DIR"

# Log files with timestamp for better organization
LOGFILE="${LOG_DIR}/${LOG_PREFIX}.log"
ERROR_LOG="${LOG_DIR}/${LOG_PREFIX}-errors.log"
DEBUG_LOG="${LOG_DIR}/${LOG_PREFIX}-debug.log"
ATTACH_LOG="${LOG_DIR}/${LOG_PREFIX}-attachments.log"
ALL_IDS_PROCESSED="${LOG_DIR}/${LOG_PREFIX}-all-ids.log"
ATTACH_ORPHANS_LOG="${LOG_DIR}/${LOG_PREFIX}-attachments-orphans.log"
STATS_LOG="${LOG_DIR}/${LOG_PREFIX}-stats.log"

# Archive previous run logs if they exist
if [ -f "$LOGFILE" ]; then
  echo "Archiving previous log files to ${LOG_DIR}/archive/..."
  mkdir -p "${LOG_DIR}/archive/${LOG_TIMESTAMP}"
  mv "${LOG_DIR}/${LOG_PREFIX}"*.log "${LOG_DIR}/archive/${LOG_TIMESTAMP}/" 2>/dev/null || true
fi

# Clean current logs
> "$LOGFILE"
> "$ERROR_LOG"
> "$DEBUG_LOG"
> "$ATTACH_LOG"
> "$ALL_IDS_PROCESSED"
> "$ATTACH_ORPHANS_LOG"
> "$STATS_LOG"

# Logging functions for better management
log_info() {
  local message="$1"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$timestamp] [INFO] $message" | tee -a "$LOGFILE"
}

log_error() {
  local message="$1"
  local context="${2:-}"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local log_entry="[$timestamp] [ERROR] $message"
  if [[ -n "$context" ]]; then
    log_entry="$log_entry | Context: $context"
  fi
  echo "$log_entry" | tee -a "$ERROR_LOG" | tee -a "$LOGFILE"
}

log_success() {
  local message="$1"
  local id="${2:-}"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local log_entry="[$timestamp] [SUCCESS] $message"
  if [[ -n "$id" ]]; then
    log_entry="$log_entry (id: $id)"
  fi
  echo "$log_entry" | tee -a "$LOGFILE"
}

log_debug() {
  local message="$1"
  local command="${2:-}"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  if [[ -n "$command" ]]; then
    echo "[$timestamp] [DEBUG] $message | CMD: $command" | tee -a "$DEBUG_LOG"
  else
    echo "[$timestamp] [DEBUG] $message" | tee -a "$DEBUG_LOG"
  fi
}

log_attachment() {
  local level="$1"
  local message="$2"
  local id="${3:-}"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local log_entry="[$timestamp] [$level] $message"
  if [[ -n "$id" ]]; then
    log_entry="$log_entry (id: $id)"
  fi
  echo "$log_entry" | tee -a "$ATTACH_LOG"
}

log_entry_separator() {
  local entry_num="$1"
  local action="${2:-START}"
  echo "================== $action ENTRY $entry_num =================" | tee -a "$LOGFILE"
}

log_stats() {
  local key="$1"
  local value="$2"
  echo "$key: $value" >> "$STATS_LOG"
}

usage() {
  echo "Usage: $0 <lastpass-backup.json> <attachments_dir> <output.kdbx>"
  exit 1
}

if [ $# -ne 3 ]; then
  usage
fi

JSON_FILE="$1"
ATTACH_DIR="$2"
KDBX_FILE="$3"

# Clean previous logs
> "$LOGFILE"
> "$ERROR_LOG"
> "$DEBUG_LOG"
> "$ATTACH_LOG"
> "$ALL_IDS_PROCESSED"
> "$ATTACH_ORPHANS_LOG"

if ! command -v keepassxc-cli >/dev/null 2>&1; then
  echo "keepassxc-cli is required. Install with 'brew install keepassxc'"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install with 'brew install jq'"
  exit 1
fi

if [ -f "$KDBX_FILE" ]; then
  echo "Output file $KDBX_FILE already exists. Remove it or choose another name."
  exit 1
fi

read -s -p "Enter new KeePass master password: " KP_PASS
export KP_PASS

echo
# 1. Create new database
echo "Creating KeePass database $KDBX_FILE..."
echo -e "$KP_PASS\n$KP_PASS" | keepassxc-cli db-create "$KDBX_FILE" --set-password >> "$DEBUG_LOG" 2>&1

# 2. Import entries from JSON
# Create main group if not exists
printf "%s\n" "$KP_PASS" | keepassxc-cli mkdir "$KDBX_FILE" "Imported" >> "$DEBUG_LOG" 2>&1
# Funzione per bonificare i nomi delle cartelle: solo lettere e numeri, tutto attaccato
sanitize_group() {
  echo "$1" | iconv -c -t ASCII//TRANSLIT | sed 's/[^[:alnum:]]//g'
}
# Funzione per estrarre l'ultimo segmento del gruppo (dopo / o \)
last_group_segment() {
  local g="$1"
  g="${g##*/}"   # dopo ultimo /
  g="${g##*\\}"  # dopo ultimo \
  echo "$g"
}
# Funzione per costruire il percorso della cartella secondo le nuove regole
build_entry_group_path() {
  local share="$1"
  local group="$2"
  local path=""
  if [[ -n "$share" && "$share" != "empty" ]]; then
    path="$share"
  fi
  if [[ -n "$group" && "$group" != "empty" ]]; then
    # Sostituisci tutte le occorrenze di \\ (doppio backslash) e / con /, poi anche le singole \ con /
    local group_path=$(echo "$group" | sed 's/\\\\/\//g; s/\//\//g; s/\\/\//g')
    if [[ -n "$path" ]]; then
      path="$path/$group_path"
    else
      path="$group_path"
    fi
  fi
  # Se path è ancora vuoto, fallback
  if [[ -z "$path" ]]; then
    path="Misc"
  fi
  echo "$path"
}
# Funzione per creare ricorsivamente tutte le sottocartelle (con spazi e caratteri originali)
create_group() {
  local parent="$1"
  local group_path="$2"
  local full_path="$parent"
  IFS='/' read -ra parts <<< "$group_path"
  for part in "${parts[@]}"; do
    if [[ -n "$part" ]]; then
      if [[ -z "$full_path" ]]; then
        full_path="$part"
      else
        full_path="$full_path/$part"
      fi
      if ! printf "%s\n" "$KP_PASS" | keepassxc-cli ls "$KDBX_FILE" "$full_path" >> "$DEBUG_LOG" 2>&1; then
        if ! printf "%s\n" "$KP_PASS" | keepassxc-cli mkdir "$KDBX_FILE" "$full_path" >> "$DEBUG_LOG" 2>&1; then
          echo "[ERROR] Failed to create group: $full_path, falling back to Misc" | tee -a "$ERROR_LOG" >> "$LOGFILE"
          echo "Misc"
          return
        fi
        echo "[LOG] Created group: $full_path" >> "$LOGFILE"
      fi
    fi
  done
  echo "$full_path"
}

ENTRY_COUNT=$(jq length "$JSON_FILE")
echo "Importing $ENTRY_COUNT entries..."
SUCCESS_COUNT=0
ERROR_COUNT=0
for i in $(seq 0 $((ENTRY_COUNT-1))); do
  entry_json=$(jq ".[$i][0]" "$JSON_FILE")
  # Check if entry_json is an object
  if ! echo "$entry_json" | jq -e 'type == "object"' >/dev/null; then
    id="(not extracted)"
    log_error "Record $i is not a valid object" "index $i"
    log_attachment "SKIP" "id: $id (index $i) - invalid record, skipping attachments"
    ((ERROR_COUNT++))
    continue
  fi
  title=$(echo "$entry_json" | jq -r '.name // "No Title"')
  username=$(echo "$entry_json" | jq -r '.username // empty')
  password=$(echo "$entry_json" | jq -r '.password // empty')
  url=$(echo "$entry_json" | jq -r '.url // empty')
  notes=$(echo "$entry_json" | jq -r '.note // empty')
  id=$(echo "$entry_json" | jq -r '.id // empty')
  group=$(echo "$entry_json" | jq -r '.group // empty')
  share=$(echo "$entry_json" | jq -r '.share // empty')
  fullname=$(echo "$entry_json" | jq -r '.fullname // empty')

  # Se è solo una cartella (name vuoto e fullname termina con /), crea solo la cartella e passa oltre
  if [[ -z "$title" && "$fullname" =~ /$ ]]; then
    entry_group_path=$(build_entry_group_path "$share" "$group")
    create_group "" "$entry_group_path" > /dev/null
    log_debug "Skipped JSON item $i: only a folder (id: $id, group: $group, share: $share)"
    continue
  fi

  # Costruisci il percorso della cartella secondo le nuove regole
  entry_group_path=$(build_entry_group_path "$share" "$group")
  # Crea tutte le sottocartelle necessarie
  parent_group=$(create_group "" "$entry_group_path")

  # Logga l'id processato per il controllo orfani allegati
  echo "$id" >> "$ALL_IDS_PROCESSED"

  # Pulizia minima del titolo (solo per evitare errori di KeePassXC)
  clean_field() {
    local val="$1"
    val=$(echo "$val" | iconv -c -t ASCII//TRANSLIT | sed 's/[[:cntrl:]]//g')
    # Sostituisci / con _ per evitare errori di percorso
    val=$(echo "$val" | sed 's|/|_|g')
    echo "$val"
  }
  safe_title=$(clean_field "$title")
  if [[ -z "$safe_title" || ${#safe_title} -lt 3 ]]; then
    safe_title="Untitled-$id"
    log_error "Title for id $id was empty or invalid, replaced with $safe_title"
  fi

  entry_path="$parent_group/$safe_title"
  orig_entry_path="$entry_path"
  suffix=1
  while printf "%s\n" "$KP_PASS" | keepassxc-cli show "$KDBX_FILE" "$entry_path" >> "$DEBUG_LOG" 2>&1; do
    if [[ -n "$username" ]]; then
      entry_path="$parent_group/${safe_title} ($username)"
    else
      entry_path="$parent_group/${safe_title} [$id]"
    fi
    if printf "%s\n" "$KP_PASS" | keepassxc-cli show "$KDBX_FILE" "$entry_path" >> "$DEBUG_LOG" 2>&1; then
      entry_path="$parent_group/${safe_title} [$suffix]"
      ((suffix++))
    fi
  done
  if [[ "$entry_path" != "$orig_entry_path" ]]; then
    log_debug "Renamed duplicate entry" "'$orig_entry_path' to '$entry_path'"
  fi
  notes_with_id="LastPassID: $id"
  if [[ -n "$notes" ]]; then
    # If notes are too large, encode in base64 and mark
    if [[ ${#notes} -gt 2048 ]]; then
      notes_b64=$(echo -n "$notes" | base64 | tr -d '\n')
      notes_with_id="$notes_with_id\nBASE64_ENCODED:\n$notes_b64"
      echo "[WARNING] Notes for id $id were too large and have been base64-encoded" | tee -a "$ERROR_LOG" >> "$LOGFILE"
    else
      notes_with_id="$notes_with_id\n$notes"
    fi
  fi
  echo "[DEBUG] CMD: keepassxc-cli add -u '$username' --url '$url' --notes (LastPassID in notes) '$KDBX_FILE' '$entry_path'" >> "$LOGFILE"
  # Crea la voce con username e password tramite password-prompt
  if ! printf "%s\n%s\n" "$KP_PASS" "$password" | keepassxc-cli add -u "$username" --password-prompt --url "$url" --notes "$notes_with_id" "$KDBX_FILE" "$entry_path" >> "$DEBUG_LOG" 2>err.log; then
    log_error "add $entry_path (id: $id, group: $group, title: $title)"
    cat err.log >> "$ERROR_LOG"
    echo "[USERPASS-ERROR] LastPassID: $id | Username: $username | Password: $password" >> "${LOG_DIR}/${LOG_PREFIX}-userpass-errors.log"
    cat err.log >> "${LOG_DIR}/${LOG_PREFIX}-userpass-errors.log"
    echo "----------------------" >> "${LOG_DIR}/${LOG_PREFIX}-userpass-errors.log"
    ((ERROR_COUNT++))
    log_entry_separator "$i" "END"
    continue
  fi
  log_success "Entry created: $entry_path" "$id"
  ((SUCCESS_COUNT++))
  # Attachments for entry
  ATTACH_PATH="$ATTACH_DIR/$id"
  shopt -s nullglob
  files=("$ATTACH_PATH"/*)
  shopt -u nullglob
  if [[ -d "$ATTACH_PATH" && ${#files[@]} -gt 0 ]]; then
    echo "Searching for attachments for id $id in $ATTACH_PATH and adding them to $entry_path"
    log_attachment "DEBUG" "Attachments for id: $id, ATTACH_PATH: $ATTACH_PATH, files: ${files[*]}" "$id"
    for file in "${files[@]}"; do
      fname="$(basename -- "$file")"
      log_attachment "DEBUG" "Current attachment: $file (fname: $fname) -> $entry_path" "$id"
      if printf '%s\n' "$KP_PASS" | keepassxc-cli attachment-import "$KDBX_FILE" "$entry_path" "$fname" "$file" >> "$DEBUG_LOG" 2>err.log; then
        log_attachment "SUCCESS" "Attachment $fname imported into $entry_path" "$id"
      else
        log_attachment "ERROR" "Attachment $fname NOT imported into $entry_path" "$id"
        cat err.log >> "$ATTACH_LOG"
      fi
    done
  fi
  log_entry_separator "$i" "END"
done

echo "\n--- IMPORT SUMMARY ---" | tee -a "$LOGFILE"
log_stats "Total elements in JSON" "$ENTRY_COUNT"
log_stats "Successfully imported" "$SUCCESS_COUNT"
log_stats "Errors" "$ERROR_COUNT"
if [[ $ENTRY_COUNT -ne $((SUCCESS_COUNT+ERROR_COUNT)) ]]; then
  log_error "Count mismatch!"
fi

echo "Detailed log in $LOGFILE, errors in $ERROR_LOG, debug in $DEBUG_LOG."
echo "Done! KeePass database created in $KDBX_FILE."

# Dopo la creazione della cartella Imported
# Salva i file di esportazione come allegati in EXPORT-LASTPASS
EXPORT_ENTRY="Imported/EXPORT-LASTPASS"

# Crea la voce EXPORT-LASTPASS
printf "%s\n" "$KP_PASS" | keepassxc-cli add "$KDBX_FILE" "$EXPORT_ENTRY" --notes "Backup LastPass export files (json, csv, attachments tgz)" >> "$DEBUG_LOG" 2>&1

# Aggiungi il file JSON
if [ -f "backup/lastpass-backup.json" ]; then
  printf "%s\n" "$KP_PASS" | keepassxc-cli attachment-import "$KDBX_FILE" "$EXPORT_ENTRY" "lastpass-backup.json" "backup/lastpass-backup.json" >> "$DEBUG_LOG" 2>&1
fi
# Aggiungi il file CSV se esiste
if [ -f "backup/lastpass-backup.csv" ]; then
  printf "%s\n" "$KP_PASS" | keepassxc-cli attachment-import "$KDBX_FILE" "$EXPORT_ENTRY" "lastpass-backup.csv" "backup/lastpass-backup.csv" >> "$DEBUG_LOG" 2>&1
fi
# Aggiungi il file LOG se esiste
if [ -f "backup/backup-debug.log" ]; then
  printf "%s\n" "$KP_PASS" | keepassxc-cli attachment-import "$KDBX_FILE" "$EXPORT_ENTRY" "backup-debug.log" "backup/lbackup-debug.log" >> "$DEBUG_LOG" 2>&1
fi
# Crea tgz della cartella attachments escludendo file MacOS
if [ -d "backup/attachments" ]; then
  tar --exclude='._*' --exclude='.DS_Store' --exclude='.Trashes' --exclude='.Spotlight-V100' -czf "/tmp/attachments.tgz" -C "backup" attachments
  printf "%s\n" "$KP_PASS" | keepassxc-cli attachment-import "$KDBX_FILE" "$EXPORT_ENTRY" "attachments.tgz" "/tmp/attachments.tgz" >> "$DEBUG_LOG" 2>&1
  rm -f /tmp/attachments.tgz
fi
