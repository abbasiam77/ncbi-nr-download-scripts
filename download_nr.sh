#!/bin/bash
# Usage: bash download_nr.sh

cd /mnt/f/ncbi-blastdb

while read file; do
  wget -c https://ftp.ncbi.nlm.nih.gov/blast/db/$file
done < nr_parts.txt
