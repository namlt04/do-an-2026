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
# 
#
homedir=$1
# destdir includes the container 
destdir=$2
dbg=/tmp/pregrade.log
cd $homedir/$destdir
is_sqlite=`which sqlite3`
if [ ! -z $is_sqlite ]; then
   #echo $is_sqlite
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
# dso-docker-escape - chuan hoa bang chung thanh cac file "OK"/"" don gian de
# results.config/goals.config so sanh (tranh phai tin vao cu phap AND/NOT chua kiem
# chung duoc cua goals.config; toan bo logic to hop nam o day, trong bash).
#
# homedir/destdir da duoc set o dau file (vd: destdir = "app").
# ---------------------------------------------------------------------------
outdir="$homedir/$destdir/.local/result"
mkdir -p "$outdir" 2>/dev/null

# Placeholder cho file feeding boolean (host_evidence.txt -> escape_via_socket;
# flag_result.txt -> get_flag/lab_complete) de checkwork khong vo ("unknown token")
# khi SV cham luc CHUA giai. Gia tri khong khop parameter.* nen van cham N dung.
if [[ "$destdir" == *app* ]]; then
  [ -s "$homedir/$destdir/host_evidence.txt" ] || echo "__MISSING__" > "$homedir/$destdir/host_evidence.txt"
  [ -s "$homedir/$destdir/flag_result.txt" ]  || echo "__MISSING__" > "$homedir/$destdir/flag_result.txt"
fi

# ---- Nhiem vu 1: recon_container ----
# "OK" neu ~/recon.txt chua >=1 trong 3 dau hieu cau hinh sai
recon_ok="NO"
if [ -f "$homedir/$destdir/recon.txt" ]; then
    if grep -qi "docker.sock" "$homedir/$destdir/recon.txt" 2>/dev/null \
       || grep -qi "cap_sys_admin" "$homedir/$destdir/recon.txt" 2>/dev/null \
       || grep -Eq "/dev/sd[a-z]" "$homedir/$destdir/recon.txt" 2>/dev/null; then
        recon_ok="OK"
    fi
fi
echo "$recon_ok" > "$outdir/recon_ok.txt"

# ---- Nhiem vu 2: bang chung hanh vi (khong chi file) - lenh docker that trong history ----
# Chong viec sinh vien echo/gia mao gia tri canary ma khong thuc su goi docker.sock.
escape_cmd_ok="NO"
if [ -f "$homedir/$destdir/.bash_history" ]; then
    if grep -E "docker[^|]*(-H|--host)[^|]*run[^|]*-v[[:space:]]*/[[:space:]]*:" \
         "$homedir/$destdir/.bash_history" >/dev/null 2>&1; then
        escape_cmd_ok="OK"
    fi
fi
echo "$escape_cmd_ok" > "$outdir/escape_cmd_ok.txt"

# ---- Nhiem vu 5: harden_container ----
# "OK" neu hardened_run.sh KHONG --privileged, KHONG docker.sock, CO --cap-drop=ALL,
# VA hardening_map.txt ton tai + khong rong.
harden_ok="NO"
hr="$homedir/$destdir/hardened_run.sh"
hm="$homedir/$destdir/hardening_map.txt"
if [ -f "$hr" ] && [ -f "$hm" ] && [ -s "$hm" ]; then
    # Bo qua dong comment ('#') de tranh false-positive khi SV ghi chu thich
    # kieu "KHONG --privileged, KHONG docker.sock" trong hardened_run.sh.
    hr_eff=$(grep -vE '^[[:space:]]*#' "$hr")
    if ! printf '%s' "$hr_eff" | grep -q -- "--privileged" \
       && ! printf '%s' "$hr_eff" | grep -q "docker.sock" \
       && printf '%s' "$hr_eff" | grep -q -- "--cap-drop=ALL"; then
        harden_ok="OK"
    fi
fi
echo "$harden_ok" > "$outdir/harden_ok.txt"
