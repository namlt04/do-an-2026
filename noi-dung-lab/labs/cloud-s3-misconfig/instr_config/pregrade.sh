#!/bin/bash
: <<'END'
This software was created by United States Government employees at
The Center for Cybersecurity and Cyber Operations (C3O)
at the Naval Postgraduate School NPS.  Please note that within the
United States, copyright protection is not available for any works
created  by United States Government employees, pursuant to Title 17
United States Code Section 105.   This software is in the public
domain and is not subject to copyright.
END
#
# Script to run prior to grading a student's lab.  It is intended
# for two potential purposes:
# 1) Create solution artifacts to campare against student artifacts;
# 2) Process student artifacts into a different form, e.g., extracting
#    browser sqlite data as in the default instance of this file below.
#
homedir=$1
# destdir includes the container
destdir=$2
dbg=/tmp/pregrade.log
cd "$homedir/$destdir" 2>/dev/null || exit 0

is_sqlite=`which sqlite3`
if [ ! -z "$is_sqlite" ]; then
   here=`pwd`
   places=$here/.mozilla/firefox/*default/places.sqlite
   for fname in $(ls $places 2> /dev/null); do
     if [[ -f $fname ]]; then
        outpath=$here/.local/result
        outfile=$outpath/moz_places.txt
        mkdir -p "$outpath"
        sqlite3 "$fname" "SELECT moz_places.* FROM moz_places;" >"$outfile"
     fi
   done
fi

#
#  Add other processing below.
#

# ---------------------------------------------------------------------------
# cloud-s3-misconfig: chuan hoa cac file bang chung tren `client` TRUOC khi
# instr_config/goals.config so sanh chung — cat CR/LF va khoang trang thua o
# cuoi file, de tranh false-negative chi vi SV dung `echo`/redirect co xuong
# dong khac voi gia tri parameter (khong co newline cuoi).
# ---------------------------------------------------------------------------
if [ "$destdir" = "client" ]; then
  for f in loot.txt creds_access_key.txt creds_secret_key.txt \
           recon_list_status.txt recon_policy_status.txt \
           harden_anon_status.txt harden_versioning_status.txt; do
    if [ -f "$f" ]; then
      tr -d '\r' < "$f" | sed -e 's/[[:space:]]*$//' > "${f}.norm" 2>/dev/null \
        && mv "${f}.norm" "$f"
    fi
  done
fi
