# NCBI nr Download Scripts

Scripts and instructions for **resumable downloading** of the NCBI non-redundant (nr) BLAST database.

## Usage

Open your Ubuntu/WSL terminal and run:

cd /mnt/f/ncbi-blastdb
while read file; do wget -c https://ftp.ncbi.nlm.nih.gov/blast/db/$file; done < nr_parts.txt

nr_parts.txt should contain the list of all required nr.*.tar.gz part filenames (one per line).

## Tips

- You can restart the download any time—only missing or incomplete parts will be resumed.
- Make sure you have enough disk space for the entire database.

## Author

Amir Ali Abbasi
Professor
National Center for Bioinformatics
Quaid-i-Azam University, Islamabad, Pakistan
Email: abbasiam@qau.edu.pk
