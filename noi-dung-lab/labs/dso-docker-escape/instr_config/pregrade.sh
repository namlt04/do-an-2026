#!/bin/bash
homedir=$1
destdir=$2
dbg=/tmp/pregrade.log
cd $homedir/$destdir
is_sqlite=`which sqlite3`
if [ ! -z $is_sqlite ]; then
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

outdir="$homedir/$destdir/.local/result"
mkdir -p "$outdir" 2>/dev/null

if [[ "$destdir" == *app* ]]; then
  [ -s "$homedir/$destdir/host_evidence.txt" ] || echo "__MISSING__" > "$homedir/$destdir/host_evidence.txt"
  [ -s "$homedir/$destdir/flag_result.txt" ]  || echo "__MISSING__" > "$homedir/$destdir/flag_result.txt"
fi

recon_ok="NO"
if [ -f "$homedir/$destdir/recon.txt" ]; then
    if grep -qi "docker.sock" "$homedir/$destdir/recon.txt" 2>/dev/null \
       || grep -qi "cap_sys_admin" "$homedir/$destdir/recon.txt" 2>/dev/null \
       || grep -Eq "/dev/sd[a-z]" "$homedir/$destdir/recon.txt" 2>/dev/null; then
        recon_ok="OK"
    fi
fi
echo "$recon_ok" > "$outdir/recon_ok.txt"

escape_cmd_ok="NO"
if [ -f "$homedir/$destdir/.bash_history" ]; then
    if grep -E "docker[^|]*(-H|--host)[^|]*run[^|]*-v[[:space:]]*/[[:space:]]*:" \
         "$homedir/$destdir/.bash_history" >/dev/null 2>&1; then
        escape_cmd_ok="OK"
    fi
fi
echo "$escape_cmd_ok" > "$outdir/escape_cmd_ok.txt"

harden_ok="NO"
hr="$homedir/$destdir/hardened_run.sh"
hm="$homedir/$destdir/hardening_map.txt"
if [ -f "$hr" ] && [ -f "$hm" ] && [ -s "$hm" ]; then
    hr_eff=$(grep -vE '^[[:space:]]*#' "$hr")
    if ! printf '%s' "$hr_eff" | grep -q -- "--privileged" \
       && ! printf '%s' "$hr_eff" | grep -q "docker.sock" \
       && printf '%s' "$hr_eff" | grep -q -- "--cap-drop=ALL"; then
        harden_ok="OK"
    fi
fi
echo "$harden_ok" > "$outdir/harden_ok.txt"
