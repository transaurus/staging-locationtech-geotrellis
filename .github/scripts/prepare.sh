#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/locationtech/geotrellis"
BRANCH="master"
REPO_DIR="source-repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Clone (skip if already exists) ---
if [ ! -d "$REPO_DIR" ]; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# --- Node version ---
# Docusaurus 2.4.3 requires Node 20 for File/ReadableStream globals (undici)
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -f "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm use 20
fi

node --version
npm --version

# --- Enter Docusaurus root ---
cd website

# --- Copy docs-mdoc → website/docs ---
# The website/docs directory doesn't exist in the repo.
# Docs live at docs-mdoc/ at the repo root level.
# Symlink causes SSR path issues so we copy instead.
if [ ! -d "docs" ]; then
    echo "[INFO] Copying docs-mdoc → website/docs"
    cp -r ../docs-mdoc docs
fi

# --- Upgrade Docusaurus to 2.4.3 ---
# The repo ships alpha.69 which has no write-translations command.
# 2.4.3 is the last stable 2.x release and has write-translations.
# Also upgrade React to 17 and @mdx-js/react to match.
echo "[INFO] Upgrading Docusaurus to 2.4.3 in package.json"
node -e "
const fs = require('fs');
const pkg = require('./package.json');
pkg.dependencies['@docusaurus/core'] = '2.4.3';
pkg.dependencies['@docusaurus/preset-classic'] = '2.4.3';
pkg.dependencies['@mdx-js/react'] = '^1.6.22';
pkg.dependencies['react'] = '^17.0.2';
pkg.dependencies['react-dom'] = '^17.0.2';
fs.writeFileSync('./package.json', JSON.stringify(pkg, null, 2));
console.log('[INFO] package.json patched');
"
rm -f yarn.lock

# --- Apply fixes.json if present ---
FIXES_JSON="$SCRIPT_DIR/fixes.json"
if [ -f "$FIXES_JSON" ]; then
    echo "[INFO] Applying content fixes..."
    node -e "
    const fs = require('fs');
    const path = require('path');
    const fixes = JSON.parse(fs.readFileSync('$FIXES_JSON', 'utf8'));
    for (const [file, ops] of Object.entries(fixes.fixes || {})) {
        if (!fs.existsSync(file)) { console.log('  skip (not found):', file); continue; }
        let content = fs.readFileSync(file, 'utf8');
        for (const op of ops) {
            if (op.type === 'replace' && content.includes(op.find)) {
                content = content.split(op.find).join(op.replace || '');
                console.log('  fixed:', file, '-', op.comment || '');
            }
        }
        fs.writeFileSync(file, content);
    }
    for (const [file, cfg] of Object.entries(fixes.newFiles || {})) {
        const c = typeof cfg === 'string' ? cfg : cfg.content;
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, c);
        console.log('  created:', file);
    }
    "
fi

# --- Package manager: yarn classic v1 ---
if ! command -v yarn &>/dev/null; then
    npm install -g yarn
fi

yarn --version

# --- Dependencies ---
yarn install --ignore-engines

echo "[DONE] Repository is ready for docusaurus commands."
