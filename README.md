CBI nr Download (MD5-verified, resumable, lock-safe)

This repository contains a reliable script, download_nr.sh, to fetch the NCBI BLAST nr database parts (nr.000.tar.gz … nr.122.tar.gz) with resume, MD5 verification, automatic retries, and single-instance locking.

Key features
------------
- Resumable downloads (wget -c into *.part, atomically promoted on success)
- Lock-safe (prevents concurrent runs with flock)
- Integrity-checked against NCBI’s .md5 files
- Idempotent: verified parts are recorded in completed_files.txt and skipped on re-runs
- Focus mode: optional requeue.txt lets you re-download only selected parts
- Self-healing: quarantines suspicious files and retries cleanly

Quick start
-----------
    # clone/update your repo as usual, then:
    cd /mnt/f/ncbi-blastdb
    bash /path/to/download_nr.sh

Interruptions are fine—just run it again. Verified parts are skipped; partial files resume.

What the script creates
-----------------------
- completed_files.txt – one line per successfully verified nr.NNN.tar.gz
- download_log.txt – append-only log of actions and errors
- download.lock – prevents overlapping runs (removed automatically)
- nr.NNN.tar.gz.part – partial/in-progress downloads
- nr.NNN.tar.gz.bad.<ts> – an existing final file failed MD5; moved aside
- nr.NNN.tar.gz.failed.<ts> – gzip/tar integrity failed; will be re-fetched next time
- nr.NNN.tar.gz.md5fail.<ts> – gzip/tar OK but MD5 mismatch (kept for manual inspection)

Defaults & overrides
--------------------
By default the script downloads 123 files (nr.000 … nr.122) into /mnt/f/ncbi-blastdb. You can override via environment variables:

Variable           Default                               Purpose
--------           -------                               -------
TARGET_DIR         /mnt/f/ncbi-blastdb                   Destination directory
MAX                122                                   Highest index (inclusive). 000..122 ⇒ 123 files
RETRY_LIMIT        5                                     Retries for fetching .md5
MD5_RETRY_LIMIT    3                                     Verify/re-fetch cycles for the .tar.gz.part
NCBI_BASE          https://ftp.ncbi.nlm.nih.gov/blast/db Source URL base
COMPLETED_LIST     completed_files.txt                   Ledger of verified parts
LOG                download_log.txt                      Log file
LOCKFILE           download.lock                         Guard file
FOCUS_LIST         requeue.txt                           If present & non-empty, only these parts are processed

Examples:
    # Change destination and number of parts
    TARGET_DIR=/data/blastdb MAX=130 bash download_nr.sh

    # Focus mode: re-download only specific files
    printf "nr.057.tar.gz\nnr.089.tar.gz\n" > /mnt/f/ncbi-blastdb/requeue.txt
    bash download_nr.sh

Minimal verification (optional, on-screen)
------------------------------------------
    cd /mnt/f/ncbi-blastdb
    MAX=122
    ok=0; bad=0
    while read -r f; do
      if md5sum -c --quiet "$f.md5" 2>/dev/null; then ((ok++)); else echo "BAD $f"; ((bad++)); fi
    done < <(seq -w 000 $MAX | awk '{printf "nr.%s.tar.gz\n",$1}')
    echo "OK=$ok  BAD=$bad"

Notes for WSL/Windows users
---------------------------
- Downloading to /mnt/f/... (Windows drive) is fine, but large I/O can be slower than native Linux (ext4).
- For best performance, consider extracting on a Linux path (e.g., ~/blastdb_nr) and set BLASTDB there.
- Add a Windows Defender exclusion for F:\ncbi-blastdb to avoid per-file scanning slowdowns.

Extraction (separate step)
--------------------------
Once all parts are verified, extract them (examples):

    # simple (no resume awareness)
    cd /mnt/f/ncbi-blastdb
    for a in nr.*.tar.gz; do
      echo "Extracting $a"
      tar -xzf "$a"
    done

For a resume-safe extractor with progress and multi-threaded gzip (pigz), see extract_all.sh (optional companion script).

Troubleshooting
---------------
- “Another instance is already running. Exiting.”
  A previous run is active. If you’re sure it isn’t, check and remove the lock:
      pgrep -af download_nr.sh || rm -f /mnt/f/ncbi-blastdb/download.lock

- Repeated MD5 failures
  See files named *.md5fail.<ts>. Keep one and compare to a fresh download to diagnose proxies/mirroring issues.

- Low throughput on /mnt/f
  Typical under WSL. Add Defender exclusions, use USB 3.0, or switch to an ext4 path inside WSL for extraction.

Author
------
Amir Ali Abbasi
Professor, National Center for Bioinformatics
Quaid-i-Azam University, Islamabad, Pakistan
Email: abbasiam@qau.edu.pk
