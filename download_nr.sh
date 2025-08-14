#!/usr/bin/env bash
# Reliable NCBI NR downloader with resume + MD5 verification.
# - Resumable downloads (.part), verified via MD5, with retries
# - Skips already completed files (completed_files.txt)
# - Prevents concurrent runs (flock)
# - Optional focus mode: if requeue.txt exists (one filename per line),
#   only those files are processed.
#
# Env overrides (optional):
#   TARGET_DIR=/mnt/f/ncbi-blastdb  MAX=122  RETRY_LIMIT=5  MD5_RETRY_LIMIT=3
#   NCBI_BASE=https://ftp.ncbi.nlm.nih.gov/blast/db
#
set -Eeuo pipefail

TARGET_DIR="${TARGET_DIR:-/mnt/f/ncbi-blastdb}"
MAX="${MAX:-122}"
RETRY_LIMIT="${RETRY_LIMIT:-5}"
MD5_RETRY_LIMIT="${MD5_RETRY_LIMIT:-3}"
NCBI_BASE="${NCBI_BASE:-https://ftp.ncbi.nlm.nih.gov/blast/db}"
COMPLETED_LIST="${COMPLETED_LIST:-completed_files.txt}"
LOG="${LOG:-download_log.txt}"
LOCKFILE="${LOCKFILE:-download.lock}"
FOCUS_LIST="${FOCUS_LIST:-requeue.txt}"

cd "$TARGET_DIR" || { echo "ERROR: Target dir not found: $TARGET_DIR"; exit 1; }

# Prevent concurrent runs
exec 9>"$LOCKFILE"
if ! flock -n 9; then
  echo "$(date -Is) Another instance is already running. Exiting." | tee -a "$LOG"
  exit 0
fi

# Flush to disk on any exit/interrupt
trap 'echo "$(date -Is) Exit/interrupt caught; syncing to disk..."; sync' EXIT INT TERM

# Ensure dos2unix is present
if ! command -v dos2unix >/dev/null 2>&1; then
  echo "dos2unix not found. Installing..." | tee -a "$LOG"
  sudo apt-get update && sudo apt-get install -y dos2unix
fi

touch "$COMPLETED_LIST"

# Build list of files to process
FILES=()
if [ -s "$FOCUS_LIST" ]; then
  echo "Focus mode: using $FOCUS_LIST" | tee -a "$LOG"
  while IFS= read -r f; do
    [ -n "${f:-}" ] && FILES+=("$f")
  done < "$FOCUS_LIST"
else
  for i in $(seq -w 000 "$MAX"); do
    FILES+=("nr.$i.tar.gz")
  done
fi

for TARFILE in "${FILES[@]}"; do
  MD5FILE="$TARFILE.md5"
  TMP="$TARFILE.part"

  # Skip if already completed
  if grep -qxF "$TARFILE" "$COMPLETED_LIST"; then
    echo "$TARFILE already completed, skipping." | tee -a "$LOG"
    continue
  fi

  echo "Processing $TARFILE ..." | tee -a "$LOG"

  # Clean up zero-byte artifacts
  [ -f "$TMP" ] && [ ! -s "$TMP" ] && { echo "Removing zero-byte $TMP" | tee -a "$LOG"; rm -f "$TMP"; }
  [ -f "$TARFILE" ] && [ ! -s "$TARFILE" ] && { echo "Removing zero-byte $TARFILE" | tee -a "$LOG"; rm -f "$TARFILE"; }

  # Download MD5 (with retries)
  tries=0
  until [ $tries -ge $RETRY_LIMIT ]; do
    if wget -q -N "$NCBI_BASE/$MD5FILE" -O "$MD5FILE"; then
      break
    fi
    tries=$((tries+1))
    echo "wget failed for $MD5FILE, attempt $tries/$RETRY_LIMIT. Retrying in 30s..." | tee -a "$LOG"
    sleep 30
  done
  if [ $tries -eq $RETRY_LIMIT ]; then
    echo "Failed to download $MD5FILE after $RETRY_LIMIT attempts. Skipping $TARFILE." | tee -a "$LOG"
    continue
  fi
  dos2unix "$MD5FILE" >/dev/null 2>&1 || true
  expected_md5=$(awk '{print $1}' "$MD5FILE")

  # Fast path: if final file exists, verify & mark OK
  if [ -f "$TARFILE" ]; then
    actual=$(md5sum "$TARFILE" | awk '{print $1}')
    if [ "$actual" = "$expected_md5" ]; then
      echo "$TARFILE downloaded and verified OK." | tee -a "$LOG"
      grep -qxF "$TARFILE" "$COMPLETED_LIST" || echo "$TARFILE" >> "$COMPLETED_LIST"
      sync
      continue
    else
      ts=$(date +%s)
      echo "Existing $TARFILE fails MD5 (have $actual, want $expected_md5). Moving aside -> $TARFILE.bad.$ts" | tee -a "$LOG"
      mv -f "$TARFILE" "$TARFILE.bad.$ts"
      sync
    fi
  fi

  # Resume/download into TMP and verify
  md5_attempts=0
  while [ $md5_attempts -lt $MD5_RETRY_LIMIT ]; do
    if [ -f "$TMP" ]; then
      echo "Resuming $TARFILE into $TMP ..." | tee -a "$LOG"
    else
      echo "Downloading $TARFILE into $TMP ..." | tee -a "$LOG"
    fi

    wget -c "$NCBI_BASE/$TARFILE" -O "$TMP"
    sync

    actual_md5=$(md5sum "$TMP" | awk '{print $1}')
    if [ "$actual_md5" = "$expected_md5" ]; then
      mv -f "$TMP" "$TARFILE"   # atomic promote
      sync
      echo "$TARFILE downloaded and verified OK." | tee -a "$LOG"
      grep -qxF "$TARFILE" "$COMPLETED_LIST" || echo "$TARFILE" >> "$COMPLETED_LIST"
      sync
      break
    else
      echo "MD5 check failed for $TARFILE (attempt $((md5_attempts+1))/$MD5_RETRY_LIMIT)." | tee -a "$LOG"
      echo "Actual MD5:   $actual_md5" | tee -a "$LOG"
      echo "Expected MD5: $expected_md5" | tee -a "$LOG"
      md5_attempts=$((md5_attempts+1))

      if [ $md5_attempts -eq $MD5_RETRY_LIMIT ]; then
        echo "Too many failed attempts. Inspecting $TMP for possible errors..." | tee -a "$LOG"
        gzip_ok=0
        tar_ok=0
        if gunzip -t "$TMP" 2>>"$LOG"; then
          echo "Gzip integrity check PASSED for $TMP" | tee -a "$LOG"
          gzip_ok=1
          if tar -tzf "$TMP" > /dev/null 2>>"$LOG"; then
            echo "Tar integrity check PASSED for $TMP" | tee -a "$LOG"
            tar_ok=1
          else
            echo "Tar integrity check FAILED for $TMP" | tee -a "$LOG"
          fi
        else
          echo "Gzip integrity check FAILED for $TMP" | tee -a "$LOG"
        fi

        ts=$(date +%s)
        if [ $gzip_ok -eq 1 ] && [ $tar_ok -eq 1 ]; then
          echo "Both integrity checks PASSED, but MD5 still fails. Renaming for manual inspection." | tee -a "$LOG"
          mv -f "$TMP" "$TARFILE.md5fail.$ts"
        else
          echo "One or both integrity checks FAILED. Moving file aside; will retry fresh next time." | tee -a "$LOG"
          mv -f "$TMP" "$TARFILE.failed.$ts"
        fi
        sync
      else
        echo "Retrying resume for $TARFILE after 10s..." | tee -a "$LOG"
        sleep 10
      fi
    fi
  done
done

echo "=== All downloads attempted ===" | tee -a "$LOG"
