#!/bin/bash
homedir=$1
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

if [ "$destdir" = "client" ]; then
  for pf in creds_access_key.txt creds_secret_key.txt; do
    [ -s "$pf" ] || printf '__MISSING__\n' > "$pf"
  done
  for f in loot.txt creds_access_key.txt creds_secret_key.txt \
           recon_list_status.txt recon_policy_status.txt \
           harden_anon_status.txt harden_versioning_status.txt; do
    if [ -f "$f" ]; then
      tr -d '\r' < "$f" | sed -e 's/[[:space:]]*$//' > "${f}.norm" 2>/dev/null \
        && mv "${f}.norm" "$f"
    fi
  done
fi
