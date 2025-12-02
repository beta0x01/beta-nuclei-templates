#!/bin/bash

# --- Configuration ---
CENT_CONFIG="$HOME/.cent.yaml"
BACKUP_CONFIG="$HOME/.cent.yaml.bak"
TEMP_HEADER="/tmp/cent_header.yaml"
REPO_LIST="/tmp/cent_repos.txt"
GIT_BRANCH=$(git branch --show-current)

# --- Ctrl+C Handler ---
# This trap catches the signal, prints a message, and allows the loop to continue
trap 'echo -e "\n\n⚠️  \033[1;31mCtrl+C Detected! Skipping current repo...\033[0m";' SIGINT

# --- 1. Preparation ---
echo -e "\n\033[1;34m[+] Starting Smart Atomic Cent Automation...\033[0m"

if [ ! -f "$CENT_CONFIG" ]; then
    echo "❌ Error: $CENT_CONFIG not found!"
    exit 1
fi

cp "$CENT_CONFIG" "$BACKUP_CONFIG"
echo "✅ Backup created at $BACKUP_CONFIG"

# --- 2. Extract Data ---
sed -n '1,/^community-templates:/p' "$BACKUP_CONFIG" > "$TEMP_HEADER"
grep -E "^\s*-\s*https://" "$BACKUP_CONFIG" > "$REPO_LIST"

TOTAL_REPOS=$(wc -l < "$REPO_LIST")
CURRENT=0

echo -e "🎯 Found \033[1;32m$TOTAL_REPOS\033[0m repositories to process."
echo -e "💡 \033[1;30mTip: Press Ctrl+C once to skip a slow repo/check.\033[0m"

# --- 3. The Execution Loop ---
while IFS= read -r repo_line; do
    ((CURRENT++))
    
    # Reset repo_url
    repo_url=$(echo "$repo_line" | sed -E 's/^\s*-\s*//')
    
    # Extract "owner/repo" for the API call
    # Removes "https://github.com/" and any trailing ".git"
    repo_slug=$(echo "$repo_url" | sed -E 's/.*github.com\///; s/\.git$//')

    echo -ne "\n\033[1;33m[+] ($CURRENT/$TOTAL_REPOS) Checking: $repo_slug ... \033[0m"

    # --- 🔎 FILE COUNT CHECK (Skippable via Ctrl+C) ---
    # We use HEAD to automatically match main/master
    file_count=$(curl -s "https://api.github.com/repos/$repo_slug/git/trees/HEAD?recursive=1" | grep '"type": "blob"' | wc -l)
    
    echo -e "📄 \033[1;36mFiles: $file_count\033[0m"

    # Create transient config
    cat "$TEMP_HEADER" > "$CENT_CONFIG"
    echo "  - $repo_url" >> "$CENT_CONFIG"

    # --- ⚙️ RUN CENT (Skippable via Ctrl+C) ---
    # If user hits Ctrl+C here, cent dies, trap fires, loop continues.
    cent --threads 100 --path templates --config "$CENT_CONFIG" > /dev/null 2>&1
    
    # --- 4. Git Operations ---
    # We only commit if the previous commands weren't skipped/failed badly
    # But strictly speaking, we just check if files changed.
    git add .

    if ! git diff --cached --quiet; then
        echo "📦 Changes detected. Committing..."
        git commit -m "feat: add templates from $repo_slug ($file_count files)"
        
        echo "🚀 Pushing..."
        git push origin "$GIT_BRANCH"
    else
        echo "💤 No changes or skipped."
    fi

done < "$REPO_LIST"

# --- 5. Cleanup ---
echo -e "\n\033[1;34m[+] Restoring original configuration...\033[0m"
mv "$BACKUP_CONFIG" "$CENT_CONFIG"
rm "$TEMP_HEADER" "$REPO_LIST"

# Reset trap so Ctrl+C works normally again
trap - SIGINT

echo -e "\n\033[1;32m💥 MISSION COMPLETE.\033[0m"
