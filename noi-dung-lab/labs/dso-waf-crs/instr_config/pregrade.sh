#!/bin/bash
# Chay tren GRADE_CONTAINER=client sau khi stoplab.
# Chi dung bash/grep/sed/awk (grader khong co jq/git).
# Tao placeholder cho moi file feeding goal de checkwork khong crash khi chua giai.
homedir=$1
destdir=$2
home="$homedir/$destdir"
out="$home/.local/result"
mkdir -p "$out"

# ---- Flag files: chuan hoa ve 1 dong (token dau tien), tao placeholder neu thieu ----
for ff in flag1.txt flag2.txt flag3.txt; do
    if [ -s "$home/$ff" ]; then
        # lay token dau tien (loai khoang trang / newline / ky tu la), giu nguyen neu la chuoi flag
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

# ---- DAST compare: can 2 bao cao, so sanh so canh bao qua WAF < truc tiep ----
ok_dast=NO
noapp="$home/dast_noWAF.txt"
wafr="$home/dast_WAF.txt"
if [ -s "$noapp" ] && [ -s "$wafr" ]; then
    c_direct=$(grep -c '^+ ' "$noapp" 2>/dev/null)
    c_waf=$(grep -c '^+ ' "$wafr" 2>/dev/null)
    [ -z "$c_direct" ] && c_direct=0
    [ -z "$c_waf" ] && c_waf=0
    # Dat OK neu: so canh bao qua WAF nho hon truc tiep, HOAC bao cao WAF co bang chung bi chan (403)
    if [ "$c_waf" -lt "$c_direct" ] || grep -qE '403|Forbidden' "$wafr"; then
        ok_dast=OK
    fi
fi
printf '%s\n' "$ok_dast" > "$out/dast_ok.txt"

exit 0
