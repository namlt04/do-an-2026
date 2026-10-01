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
# pregrade.sh - cloud-ssrf-imds
#
# Chay TRUOC khi cham (goals.config), mot lan cho tung container duoc thu
# thap artifact. Nhiem vu: doc log/artifact THO (fetch.log tren web,
# imds_access.log tren imds, remediation.txt tren client - deu la file ma
# sinh vien KHONG the tu sua tren web/imds vi khong co shell tren cac
# container do) va suy ra cac co bang chung don gian ("YES"/rong) duoi
# .local/result/*.ok. results.config chi can doc toan bo noi dung cac file
# .ok nay (khong can cu phap loc phuc tap), giup goals.config on dinh va
# de kiem chung.
#
# $1 = homedir (thu muc goc artifact da thu thap)
# $2 = destdir (ten container, vd "client", "web", "imds", "storage")

homedir=$1
destdir=$2
cd "$homedir/$destdir" || exit 0
outdir="$homedir/$destdir/.local/result"
mkdir -p "$outdir"

# -----------------------------------------------------------------------
# Container web: suy luan tu fetch.log (nhat ky /fetch cua imgproxy-portal)
# -----------------------------------------------------------------------
if [[ "$destdir" == *"web"* ]] && [ -f "fetch.log" ]; then
    # Nhiem vu 1 (discover_ssrf): co it nhat 1 request duoc CHO PHEP toi
    # dich noi bo (loopback cua webapp va/hoac IMDS, duoi bat ky bi danh nao)
    if grep -q '"internal": true' fetch.log && \
       grep '"internal": true' fetch.log | grep -q '"allowed": true'; then
        echo "YES" > "$outdir/discover_ssrf.ok"
    fi

    # Nhiem vu 2 (steal_credentials): co request CHO PHEP toi duong dan
    # security-credentials cua IMDS (chinh la buoc doc credential tam thoi)
    if grep -q 'security-credentials' fetch.log && \
       grep 'security-credentials' fetch.log | grep -q '"allowed": true'; then
        echo "YES" > "$outdir/steal_via_ssrf.ok"
    fi

    # Nhiem vu 4 (harden_ssrf_imds): sau khi bat allowlist, co request toi
    # IMDS/meta-data BI CHAN (allowed=false)
    if grep -q '"allowed": false' fetch.log && \
       grep '"allowed": false' fetch.log | grep -qE 'meta-data|"host": *"imds"|169\.254\.169\.254|172\.34\.0\.40'; then
        echo "YES" > "$outdir/harden_blocks_ssrf.ok"
    fi
fi

# -----------------------------------------------------------------------
# Container imds: suy luan tu imds_access.log
# -----------------------------------------------------------------------
if [[ "$destdir" == *"imds"* ]] && [ -f "imds_access.log" ]; then
    # IMDSv2 dang duoc thuc thi that (khong chi bat co): phai co CA HAI -
    # (a) it nhat 1 lan tu choi GET tran (401), VA
    # (b) it nhat 1 lan truy cap hop le kem token dung (has_valid_token=true)
    #     - chung minh quy trinh PUT->GET van dung, khong phai loi cai dat.
    if grep -q '"status": 401' imds_access.log && \
       grep -q '"has_valid_token": true' imds_access.log; then
        echo "YES" > "$outdir/imdsv2_enforced.ok"
    fi
fi

# -----------------------------------------------------------------------
# Container client: suy luan tu remediation.txt (Nhiem vu 4, buoc 4) va
# loot.txt (bang chung da trich duoc AccessKeyId gia o Nhiem vu 2)
# -----------------------------------------------------------------------
if [[ "$destdir" == *"client"* ]]; then
    if [ -f "remediation.txt" ] && \
       grep -qi 'allowlist' remediation.txt && \
       grep -qi 'imdsv2' remediation.txt && \
       grep -qiE 'least[ -]privilege' remediation.txt; then
        echo "YES" > "$outdir/remediation_ok.ok"
    fi

    if [ -f "creds.txt" ] && grep -q 'AccessKeyId' creds.txt; then
        echo "YES" > "$outdir/loot_accesskey.ok"
    fi
fi

exit 0
