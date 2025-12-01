#!/bin/bash

# --- Configuration ---
CENT_CONFIG="$HOME/.cent.yaml"
BACKUP_CONFIG="$HOME/.cent.yaml.bak"
TEMP_HEADER="/tmp/cent_header.yaml"
REPO_LIST="/tmp/cent_repos.txt"
GIT_BRANCH=$(git branch --show-current)

# --- 1. Preparation ---
echo -e "\n\033[1;34m[+] Starting Atomic Cent Automation...\033[0m"

if [ ! -f "$CENT_CONFIG" ]; then
    echo "❌ Error: $CENT_CONFIG not found!"
    exit 1
fi

# Backup the original config
cp "$CENT_CONFIG" "$BACKUP_CONFIG"
echo "✅ Backup created at $BACKUP_CONFIG"

# --- 2. Extract Data ---
# Extract everything UP TO 'community-templates:' (inclusive)
sed -n '1,/^community-templates:/p' "$BACKUP_CONFIG" > "$TEMP_HEADER"

# Extract only the lines containing URLs (ignoring comments/whitespace)
grep -E "^\s*-\s*https://" "$BACKUP_CONFIG" > "$REPO_LIST"

TOTAL_REPOS=$(wc -l < "$REPO_LIST")
CURRENT=0

echo -e "🎯 Found \033[1;32m$TOTAL_REPOS\033[0m repositories to process."

# --- 3. The Execution Loop ---
while IFS= read -r repo_line; do
    ((CURRENT++))
    
    # Clean the URL (remove dash and whitespace)
    repo_url=$(echo "$repo_line" | sed -E 's/^\s*-\s*//')
    
    echo -e "\n\033[1;33m[+] Processing ($CURRENT/$TOTAL_REPOS): $repo_url\033[0m"

    # Create a transient config with just THIS repo
    cat "$TEMP_HEADER" > "$CENT_CONFIG"
    echo "  - $repo_url" >> "$CENT_CONFIG"

    # Run Cent (Silent mode to reduce clutter, remove > /dev/null to debug)
    # forcing --path . as requested
    cent --threads 100 --path . > /dev/null 2>&1
    
    # --- 4. Git Operations ---
    # Add all files (including new templates)
    git add .

    # Check if we actually have something to commit
    if ! git diff --cached --quiet; then
        echo "📦 Changes detected. Committing..."
        git commit -m "feat: add templates from $repo_url"
        
        # Push immediately to keep local changes low and sync
        echo "🚀 Pushing to $GIT_BRANCH..."
        git push origin "$GIT_BRANCH"
    else
        echo "💤 No new templates from this repo. Skipping commit."
    fi

done < "$REPO_LIST"

# --- 5. Cleanup ---
echo -e "\n\033[1;34m[+] Restoring original configuration...\033[0m"
mv "$BACKUP_CONFIG" "$CENT_CONFIG"
rm "$TEMP_HEADER" "$REPO_LIST"

echo -e "\n\033[1;32m💥 MISSION COMPLETE. All templates aggregated and pushed!\033[0m"