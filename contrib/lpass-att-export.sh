#!/bin/bash
# Complete LastPass backup: CSV, JSON, attachments in subfolders by ID
# Usage: lpass-att-export.sh [-l <email>] [-o <outdir>]

# --- Cross-platform sed function (gsed on macOS, sed on Linux) ---
if [[ "$(uname)" == "Darwin" ]]; then
  if ! command -v gsed >/dev/null 2>&1; then
    echo "[INFO] gsed not found, installing with brew..."
    brew install gnu-sed || { echo "Failed to install gsed"; exit 1; }
  fi
  SED_BIN="gsed"
else
  SED_BIN="sed"
fi

sed_compat() {
  $SED_BIN "$@"
}

usage() { echo "Usage: $0 [-l <email>] [-o <outdir>]" 1>&2; exit 1; }

while getopts ":o:hl:" o; do
    case "${o}" in
        o)
            outdir=${OPTARG}
            ;;
        l)
            email=${OPTARG}
            ;;
        h)
            usage
            ;;
        *)
            usage
            ;;
    esac

done
shift $((OPTIND-1))

if [ -z "${outdir}" ]; then
    usage
fi

command -v lpass >/dev/null 2>&1 || { echo >&2 "lpass is required but not installed. Aborting."; exit 1; }

if [ ! -d ${outdir} ]; then
  echo "${outdir} does not exist. Creating directory."
  mkdir -p "${outdir}" || { echo "Failed to create directory ${outdir}."; exit 1; }
fi

if ! lpass status; then
  if [ -z ${email} ]; then
    echo "No login data found. Please login with -l or use lpass login before running this script."
    exit 1;
  fi
  lpass login ${email}
fi

# 1. CSV backup
lpass export > "${outdir}/lastpass-backup.csv"

# 2. JSON backup (valid array)
ids=$(lpass ls | sed_compat -n "s/^.*id:\s*\([0-9]*\).*$/\1/p")
echo "[" > "${outdir}/lastpass-backup.json"
first=1
for id in ${ids}; do
  json=$(lpass show -j $id 2>/dev/null)
  if [[ -n "$json" ]]; then
    if [[ $first -eq 0 ]]; then
      echo "," >> "${outdir}/lastpass-backup.json"
    fi
    echo "$json" >> "${outdir}/lastpass-backup.json"
    first=0
  fi
done
echo "]" >> "${outdir}/lastpass-backup.json"

# 3. Attachments backup in subfolders by secret ID
mkdir -p "${outdir}/attachments"
ids=$(lpass ls | sed_compat -n "s/^.*id:\s*\([0-9]*\).*$/\1/p")
for id in ${ids}; do
  attlist=$(lpass show ${id} | grep att-)
  if [ -n "$attlist" ]; then
    mkdir -p "${outdir}/attachments/${id}"
    attcount=$(echo "$attlist" | wc -l)
    for ((i=1; i<=attcount; i++)); do
      attline=$(echo "$attlist" | sed_compat -n "${i}p")
      attid=$(echo "$attline" | awk '{print $1}' | tr -d ':')
      attname=$(echo "$attline" | cut -d' ' -f2-)
      if [[ -z $attname ]]; then
        attname="attachment_${attid}"
      fi
      attname=$(echo "$attname" | sed_compat 's/^ *//;s/ *$//')
      out="${outdir}/attachments/${id}/${attname}"
      if [[ -f $out ]]; then
        out="${outdir}/attachments/${id}/${i}_$attname"
      fi
      echo "Exporting attachment: $id/$attname -> $out"
      lpass show --attach=${attid} ${id} --quiet > "$out"
    done
  fi
done

