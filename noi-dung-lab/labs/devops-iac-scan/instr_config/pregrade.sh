#!/bin/bash
homedir=$1
destdir=$2
dbg=/tmp/pregrade_devops-iac-scan.log

cd "$homedir/$destdir" 2>/dev/null || exit 0

PROJ="$PWD/iac-project"
if [ ! -d "$PROJ" ]; then
    exit 0
fi

RESULT_DIR="$PWD/.local/result"
mkdir -p "$RESULT_DIR"

if [ ! -s "$PWD/flag.txt" ]; then printf 'NOTYET\n' > "$PWD/flag.txt"; fi

echo "[devops-iac-scan] pregrade start: $(date)" > "$dbg"

NETWORK_TF="$PROJ/network.tf"
STORAGE_TF="$PROJ/storage.tf"
VARS_TF="$PROJ/variables.tf"
IAM_TF="$PROJ/iam.tf"

net_ok=1
if [ -f "$NETWORK_TF" ]; then
    if grep -vE '^[[:space:]]*#' "$NETWORK_TF" | grep -Eq '0\.0\.0\.0/0'; then
        net_ok=0
        echo "[network] 0.0.0.0/0 still present in network.tf" >> "$dbg"
    fi
else
    net_ok=0
    echo "[network] network.tf not found" >> "$dbg"
fi

store_ok=1
if [ -f "$STORAGE_TF" ]; then
    if grep -Eq '(block_public_acls|block_public_policy|ignore_public_acls|restrict_public_buckets)[[:space:]]*=[[:space:]]*false' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] public_access_block still has a flag = false" >> "$dbg"
    fi
    if ! grep -Eq '(block_public_acls|block_public_policy|ignore_public_acls|restrict_public_buckets)[[:space:]]*=[[:space:]]*true' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] missing aws_s3_bucket_public_access_block with flags = true" >> "$dbg"
    fi
    if ! grep -Eq 'aws_s3_bucket_server_side_encryption_configuration' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] missing server_side_encryption_configuration" >> "$dbg"
    fi
    if ! grep -Eq 'aws_s3_bucket_versioning' "$STORAGE_TF" || ! grep -Eqi 'status[[:space:]]*=[[:space:]]*"Enabled"' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] missing aws_s3_bucket_versioning Enabled" >> "$dbg"
    fi
    if grep -Eqi 'acl[[:space:]]*=[[:space:]]*"public-read' "$STORAGE_TF"; then
        store_ok=0
        echo "[storage] acl public-read still present" >> "$dbg"
    fi
else
    store_ok=0
    echo "[storage] storage.tf not found" >> "$dbg"
fi

if [ "$net_ok" -eq 1 ] && [ "$store_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_network_storage"
else
    printf 'FAIL' > "$RESULT_DIR/chk_network_storage"
fi

sec_ok=1
if [ -f "$VARS_TF" ]; then
    if grep -Fq 'P@ssw0rd_SuperSecret_2024!' "$VARS_TF"; then
        sec_ok=0
        echo "[secret] original db_password still hardcoded" >> "$dbg"
    fi
    if grep -Fq 'wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY' "$VARS_TF"; then
        sec_ok=0
        echo "[secret] original aws_secret_key still hardcoded" >> "$dbg"
    fi
    if ! grep -Eq 'sensitive[[:space:]]*=[[:space:]]*true' "$VARS_TF"; then
        sec_ok=0
        echo "[secret] no variable marked sensitive = true" >> "$dbg"
    fi
else
    sec_ok=0
    echo "[secret] variables.tf not found" >> "$dbg"
fi

if [ -f "$IAM_TF" ]; then
    if grep -Eq 'Action[[:space:]]*=[[:space:]]*"\*"' "$IAM_TF"; then
        sec_ok=0
        echo "[iam] Action = \"*\" still present" >> "$dbg"
    fi
    if grep -Eq 'Resource[[:space:]]*=[[:space:]]*"\*"' "$IAM_TF"; then
        sec_ok=0
        echo "[iam] Resource = \"*\" still present" >> "$dbg"
    fi
else
    sec_ok=0
    echo "[iam] iam.tf not found" >> "$dbg"
fi

if [ "$sec_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_secret_iam"
else
    printf 'FAIL' > "$RESULT_DIR/chk_secret_iam"
fi

active_flowlog=$(grep -h '^[^#]*resource[[:space:]]*"aws_flow_log"' "$PROJ"/*.tf 2>/dev/null | wc -l)
active_s3log=$(grep -h '^[^#]*resource[[:space:]]*"aws_s3_bucket_logging"' "$PROJ"/*.tf 2>/dev/null | wc -l)
if [ "$active_flowlog" -ge 1 ] && [ "$active_s3log" -ge 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_logging"
else
    printf 'FAIL' > "$RESULT_DIR/chk_logging"
    echo "[logging] active_flowlog=$active_flowlog active_s3log=$active_s3log" >> "$dbg"
fi

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
    echo "[baseline] missing or empty: $BASELINE_JSON" >> "$dbg"
fi
if [ "$base_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_baseline"
else
    printf 'FAIL' > "$RESULT_DIR/chk_baseline"
fi

after_ok=0
AFTER_JSON="$PWD/after.json"
if [ "$net_ok" -eq 1 ] && [ "$store_ok" -eq 1 ] && [ "$sec_ok" -eq 1 ]; then
    if [ -s "$AFTER_JSON" ]; then
        hc2=$(grep -o '"severity":[[:space:]]*"\(HIGH\|CRITICAL\)"' "$AFTER_JSON" 2>/dev/null | wc -l)
        if [ "$hc2" -eq 0 ]; then
            after_ok=1
        else
            echo "[after] after.json still has $hc2 HIGH/CRITICAL findings" >> "$dbg"
        fi
    else
        echo "[after] missing or empty: $AFTER_JSON" >> "$dbg"
    fi
else
    echo "[after] current source is not clean (net_ok=$net_ok store_ok=$store_ok sec_ok=$sec_ok)" >> "$dbg"
fi
if [ "$after_ok" -eq 1 ]; then
    printf 'OK' > "$RESULT_DIR/chk_after_zero"
else
    printf 'FAIL' > "$RESULT_DIR/chk_after_zero"
fi

echo "[devops-iac-scan] pregrade done: $(date)" >> "$dbg"
