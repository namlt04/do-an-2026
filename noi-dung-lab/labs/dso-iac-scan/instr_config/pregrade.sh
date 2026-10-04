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
# pregrade.sh -- dso-iac-scan
#
# Chay TRUOC khi cham diem (checkwork/gradelab), tren artifact da thu tu
# sinh vien. Muc dich: tu PHAN TICH LAI truc tiep ma Terraform (~/iac-project)
# va cac bao cao JSON thu duoc, roi ghi ra cac file danh dau
# ".local/result/chk_*" chua "OK" hoac "FAIL". goals.config chi so sanh cac
# file danh dau nay (string_equal ... answer=OK) -- vi cac file nay bi GHI DE
# lai moi lan cham diem boi chinh script nay, sinh vien echo gia noi dung cu
# vao do (hay vao baseline.json/after.json) se KHONG co tac dung.
#
# Day la lop phong thu THU HAI (defense in depth) ben canh flag: flag
# (pass_gate/_flag_ok) chi lay duoc khi container `ci` (khong co shell cho
# sinh vien) tu quet doc lap va xac nhan 0 HIGH/CRITICAL. Cac kiem tra o day
# xac nhan LAI, mot cach doc lap, rang ma Terraform hien tai thuc su da duoc
# khac phuc dung noi dung (khong chi la sinh vien copy paste 1 flag dung tu
# cho khac trong khi ma van con loi).
#
homedir=$1
# destdir includes the container
destdir=$2
dbg=/tmp/pregrade_dso-iac-scan.log

cd "$homedir/$destdir" 2>/dev/null || exit 0

# Neu khong co thu muc du an Terraform o day, day khong phai artifact cua
# container `devsecops` (vi du dang duoc goi cho container `ci`) -- bo qua.
PROJ="$PWD/iac-project"
if [ ! -d "$PROJ" ]; then
    exit 0
fi

RESULT_DIR="$PWD/.local/result"
mkdir -p "$RESULT_DIR"

echo "[dso-iac-scan] pregrade start: $(date)" > "$dbg"

NETWORK_TF="$PROJ/network.tf"
STORAGE_TF="$PROJ/storage.tf"
VARS_TF="$PROJ/variables.tf"
IAM_TF="$PROJ/iam.tf"

# ---------------------------------------------------------------------
# 1) network.tf + storage.tf ("fix_network_storage")
# ---------------------------------------------------------------------
net_ok=1
if [ -f "$NETWORK_TF" ]; then
    # Khong duoc con bat ky cidr_blocks nao mo ra toan Internet trong SG.
    # (Bo qua dong comment '#' de tranh false-positive khi SV ghi chu thich.)
    if grep -vE '^[[:space:]]*#' "$NETWORK_TF" | grep -Eq '0\.0\.0\.0/0'; then
        net_ok=0
        echo "[network] con 0.0.0.0/0 trong network.tf" >> "$dbg"
    fi
else
    net_ok=0
    echo "[network] khong tim thay network.tf" >> "$dbg"
fi

store_ok=1
if [ -f "$STORAGE_TF" ]; then
    # Khong con co public_access_block nao dat = false.
    if grep -Eq '(block_public_acls|block_public_policy|ignore_public_acls|restrict_public_buckets)[[:space:]]*=[[:space:]]*false' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] public_access_block van co co = false" >> "$dbg"
    fi
    # Phai co it nhat 1 co public_access_block dat = true (tuc da them resource chan).
    if ! grep -Eq '(block_public_acls|block_public_policy|ignore_public_acls|restrict_public_buckets)[[:space:]]*=[[:space:]]*true' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] thieu aws_s3_bucket_public_access_block voi cac co = true" >> "$dbg"
    fi
    # Phai bat ma hoa at-rest.
    if ! grep -Eq 'aws_s3_bucket_server_side_encryption_configuration' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] thieu server_side_encryption_configuration" >> "$dbg"
    fi
    # Phai bat versioning (Enabled).
    if ! grep -Eq 'aws_s3_bucket_versioning' "$STORAGE_TF" || ! grep -Eqi 'status[[:space:]]*=[[:space:]]*"Enabled"' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] thieu aws_s3_bucket_versioning Enabled" >> "$dbg"
    fi
    # Khong con acl public-read/public-read-write truc tiep tren bucket.
    if grep -Eqi 'acl[[:space:]]*=[[:space:]]*"public-read' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] con acl public-read" >> "$dbg"
    fi
else
    store_ok=0
    echo "[storage] khong tim thay storage.tf" >> "$dbg"
fi

if [ "$net_ok" -eq 1 ] && [ "$store_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_network_storage"
else
    printf 'FAIL' > "$RESULT_DIR/chk_network_storage"
fi

# ---------------------------------------------------------------------
# 2) variables.tf + iam.tf ("fix_secret_iam")
# ---------------------------------------------------------------------
sec_ok=1
if [ -f "$VARS_TF" ]; then
    # 2 gia tri bi mat gia da cam san trong baseline khong duoc con xuat hien.
    if grep -Fq 'P@ssw0rd_SuperSecret_2024!' "$VARS_TF"; then
        sec_ok=0
        echo "[secret] con hardcode db_password goc" >> "$dbg"
    fi
    if grep -Fq 'wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY' "$VARS_TF"; then
        sec_ok=0
        echo "[secret] con hardcode aws_secret_key goc" >> "$dbg"
    fi
    # Bien nhay cam phai duoc danh dau sensitive = true.
    if ! grep -Eq 'sensitive[[:space:]]*=[[:space:]]*true' "$VARS_TF"; then
        sec_ok=0
        echo "[secret] chua co bien nao duoc danh dau sensitive = true" >> "$dbg"
    fi
else
    sec_ok=0
    echo "[secret] khong tim thay variables.tf" >> "$dbg"
fi

if [ -f "$IAM_TF" ]; then
    if grep -Eq 'Action[[:space:]]*=[[:space:]]*"\*"' "$IAM_TF"; then
        sec_ok=0
        echo "[iam] con Action = \"*\"" >> "$dbg"
    fi
    if grep -Eq 'Resource[[:space:]]*=[[:space:]]*"\*"' "$IAM_TF"; then
        sec_ok=0
        echo "[iam] con Resource = \"*\"" >> "$dbg"
    fi
else
    sec_ok=0
    echo "[iam] khong tim thay iam.tf" >> "$dbg"
fi

if [ "$sec_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_secret_iam"
else
    printf 'FAIL' > "$RESULT_DIR/chk_secret_iam"
fi

# ---------------------------------------------------------------------
# 3) logging.tf (+ storage.tf) ("pass_gate" - logging)
# ---------------------------------------------------------------------
active_flowlog=$(grep -h '^[^#]*resource[[:space:]]*"aws_flow_log"' "$PROJ"/*.tf 2>/dev/null | wc -l)
active_s3log=$(grep -h '^[^#]*resource[[:space:]]*"aws_s3_bucket_logging"' "$PROJ"/*.tf 2>/dev/null | wc -l)
if [ "$active_flowlog" -ge 1 ] && [ "$active_s3log" -ge 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_logging"
else
    printf 'FAIL' > "$RESULT_DIR/chk_logging"
    echo "[logging] active_flowlog=$active_flowlog active_s3log=$active_s3log" >> "$dbg"
fi

# ---------------------------------------------------------------------
# 4) baseline_scan: baseline.json ton tai, co finding HIGH/CRITICAL, va
#    lich su lenh cho thay sinh vien da thuc su chay cong cu quet.
# ---------------------------------------------------------------------
base_ok=0
BASELINE_JSON="$PWD/baseline.json"
if [ -s "$BASELINE_JSON" ]; then
    hc=$(grep -o '"severity":[[:space:]]*"\(HIGH\|CRITICAL\)"' "$BASELINE_JSON" 2>/dev/null | wc -l)
    ran=0
    if [ -f "$PWD/.bash_history" ] && grep -Eq 'tfsec|checkov|trivy' "$PWD/.bash_history"; then
        ran=1
    fi
    if [ "$hc" -ge 1 ] && [ "$ran" -eq 1 ]; then
        base_ok=1
    else
        echo "[baseline] hc=$hc ran=$ran" >> "$dbg"
    fi
else
    echo "[baseline] khong tim thay hoac rong: $BASELINE_JSON" >> "$dbg"
fi
if [ "$base_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_baseline"
else
    printf 'FAIL' > "$RESULT_DIR/chk_baseline"
fi

# ---------------------------------------------------------------------
# 5) pass_gate - after_zero: ket hop (a) ma Terraform HIEN TAI da sach theo
#    kiem tra cau truc doc lap o buoc 1+2 (net_ok/store_ok/sec_ok), VA
#    (b) bao cao ~/after.json (neu co) cung the hien 0 HIGH/CRITICAL.
#    Ca hai cung phai dung -- sinh vien khong the chi sua after.json ma
#    khong sua ma nguon that.
# ---------------------------------------------------------------------
after_ok=0
AFTER_JSON="$PWD/after.json"
if [ "$net_ok" -eq 1 ] && [ "$store_ok" -eq 1 ] && [ "$sec_ok" -eq 1 ]; then
    if [ -s "$AFTER_JSON" ]; then
        hc2=$(grep -o '"severity":[[:space:]]*"\(HIGH\|CRITICAL\)"' "$AFTER_JSON" 2>/dev/null | wc -l)
        if [ "$hc2" -eq 0 ]; then
            after_ok=1
        else
            echo "[after] after.json van con $hc2 finding HIGH/CRITICAL" >> "$dbg"
        fi
    else
        echo "[after] khong tim thay hoac rong: $AFTER_JSON" >> "$dbg"
    fi
else
    echo "[after] ma nguon hien tai chua sach (net_ok=$net_ok store_ok=$store_ok sec_ok=$sec_ok)" >> "$dbg"
fi
if [ "$after_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_after_zero"
else
    printf 'FAIL' > "$RESULT_DIR/chk_after_zero"
fi

echo "[dso-iac-scan] pregrade done: $(date)" >> "$dbg"
