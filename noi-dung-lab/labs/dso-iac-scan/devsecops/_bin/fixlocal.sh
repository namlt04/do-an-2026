#!/bin/bash

PROJ="$HOME/iac-project"

chmod +x "$HOME/gate.sh" 2>/dev/null

if [ -d "$PROJ" ] && [ ! -d "$PROJ/.git" ]; then
    (
        cd "$PROJ" || exit 0
        git init -q
        git config user.email "dev-team@example.local"
        git config user.name "Dev Team (baseline)"
        git add -A
        git commit -q -m "baseline: ha tang Terraform ban dau tu doi dev (chua qua review bao mat)"
    )
fi

mkdir -p "$HOME/.local/result" 2>/dev/null
