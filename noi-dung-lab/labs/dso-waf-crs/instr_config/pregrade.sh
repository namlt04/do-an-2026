#!/bin/bash
# Runs on GRADE_CONTAINER=client after stoplab.
# Uses only bash/grep/sed/awk (the grader has no jq/git).
# Create a placeholder for every goal-feeding file so checkwork does not crash before solving.
homedir=$1
destdir=$2
home="$homedir/$destdir"
out="$home/.local/result"
mkdir -p "$out"

# ---- Flag files: normalize to 1 line (first token), create placeholder if missing ----
for ff in flag1.txt flag2.txt flag3.txt; do
    if [ -s "$home/$ff" ]; then
        # take the first token (strip whitespace / newline / odd chars), keep as-is if it is a flag string
        val=$(tr -d '\r' < "$home/$ff" | awk 'NF {print $1; exit}')
        if [ -n "$val" ]; then
            printf '%s\n' "$val" > "$home/$ff"
        else
            printf 'NOTYET\n' > "$home/$ff"
        fi
    else
        printf 'NOTYET\n' > "$home/$ff"
    fi
done

# ---- DAST compare: needs 2 reports, compare warning count through WAF < direct ----
ok_dast=NO
noapp="$home/dast_noWAF.txt"
wafr="$home/dast_WAF.txt"
if [ -s "$noapp" ] && [ -s "$wafr" ]; then
    c_direct=$(grep -c '^+ ' "$noapp" 2>/dev/null)
    c_waf=$(grep -c '^+ ' "$wafr" 2>/dev/null)
    [ -z "$c_direct" ] && c_direct=0
    [ -z "$c_waf" ] && c_waf=0
    # Set OK if: warning count through WAF is lower than direct, OR the WAF report has evidence of blocking (403)
    if [ "$c_waf" -lt "$c_direct" ] || grep -qE '403|Forbidden' "$wafr"; then
        ok_dast=OK
    fi
fi
printf '%s\n' "$ok_dast" > "$out/dast_ok.txt"

exit 0
