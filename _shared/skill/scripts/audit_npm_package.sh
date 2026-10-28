#!/bin/bash
# audit_npm_package.sh
#
# Automates the "Auditability" and part of the "Blast Radius" checks from
# the ai-vetting-skill-sx skill for any npm-distributed MCP server, hook,
# or plugin. Run this before trusting the README's claims.
#
# Usage: ./audit_npm_package.sh <package-name>
# Example: ./audit_npm_package.sh @brightdata/mcp

set -e

PKG="$1"
if [ -z "$PKG" ]; then
  echo "Usage: $0 <npm-package-name>"
  exit 1
fi

WORKDIR=$(mktemp -d)
cd "$WORKDIR"

echo "=================================================="
echo "AUDITING: $PKG"
echo "=================================================="

echo ""
echo "--- 1. Publication history (Provenance signal) ---"
npm view "$PKG" --json 2>/dev/null > meta.json
VERSION_COUNT=$(node -e "console.log(JSON.parse(require('fs').readFileSync('meta.json')).versions.length)" 2>/dev/null || echo "unknown")
LATEST=$(node -e "console.log(JSON.parse(require('fs').readFileSync('meta.json'))['dist-tags'].latest)" 2>/dev/null || echo "unknown")
CREATED=$(node -e "console.log(JSON.parse(require('fs').readFileSync('meta.json')).time.created)" 2>/dev/null || echo "unknown")
MODIFIED=$(node -e "console.log(JSON.parse(require('fs').readFileSync('meta.json')).time.modified)" 2>/dev/null || echo "unknown")
echo "Total published versions: $VERSION_COUNT"
echo "Latest version: $LATEST"
echo "First published: $CREATED"
echo "Last modified: $MODIFIED"
echo "  -> Single version ever published, or first-published = last-modified,"
echo "     is a red flag (brand-new or one-shot package)."

echo ""
echo "--- 2. Downloading real package contents ---"
npm pack "$PKG" 2>&1 | tail -5
TARBALL=$(ls *.tgz 2>/dev/null | head -1)
if [ -z "$TARBALL" ]; then
  echo "FAILED to download package. Stopping."
  exit 1
fi
tar xzf "$TARBALL"

echo ""
echo "--- 3. Checking package.json for install-time code execution ---"
PKGJSON=$(find package -maxdepth 1 -name package.json | head -1)
if [ -z "$PKGJSON" ]; then
  PKGJSON=$(find . -maxdepth 2 -name package.json | grep -v node_modules | head -1)
fi
if grep -q '"preinstall"\|"postinstall"\|"install"' "$PKGJSON" 2>/dev/null; then
  echo "  !! FLAG: package.json contains a pre/post/install script."
  echo "  This runs automatically on npm install, before you've reviewed anything."
  grep -A1 '"preinstall"\|"postinstall"\|"\"install\""' "$PKGJSON"
else
  echo "  OK: no preinstall/postinstall/install script found."
fi

echo ""
echo "--- 4. License check ---"
grep '"license"' "$PKGJSON" 2>/dev/null || echo "  No license field found — flag for review."

echo ""
echo "--- 5. Scanning source for dangerous patterns ---"
JSFILES=$(find package -name "*.js" 2>/dev/null)
if [ -z "$JSFILES" ]; then
  JSFILES=$(find . -name "*.js" | grep -v node_modules)
fi
HITS=$(grep -n "eval(\|child_process\|exec(\|Function(\|new Function" $JSFILES 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "  Found matches (REVIEW EACH — not all are malicious, e.g. page.\$eval is a Playwright API):"
  echo "$HITS"
else
  echo "  No eval/exec/child_process/Function() patterns found."
fi

echo ""
echo "--- 6. Every outbound URL the code references (Blast Radius signal) ---"
grep -ohE "https?://[a-zA-Z0-9./_-]+" $JSFILES 2>/dev/null | sort -u
echo "  -> Review this list: does everything point to the vendor's own domain"
echo "     and expected scrape/API targets? A call to an unrelated domain"
echo "     (analytics, pastebin, a raw IP) is a red flag worth investigating."

echo ""
echo "--- 7. Obfuscation / minification check ---"
OBFUSCATED=0
for f in $JSFILES; do
  MAXLINE=$(awk '{ print length }' "$f" 2>/dev/null | sort -rn | head -1)
  if [ -n "$MAXLINE" ] && [ "$MAXLINE" -gt 500 ]; then
    echo "  !! FLAG: $f has a line $MAXLINE characters long — likely minified/obfuscated."
    OBFUSCATED=1
  fi
done
if [ "$OBFUSCATED" -eq 0 ]; then
  echo "  OK: no minified/obfuscated files detected (source reads as normal code)."
fi

echo ""
echo "=================================================="
echo "COVERAGE LIMITATIONS — read this before trusting a clean result above"
echo "=================================================="
echo "This script performs STATIC analysis only. It does NOT:"
echo "  - Run or execute the package (the tool never actually starts)."
echo "  - Catch runtime-only behavior (e.g. logic gated on an API response,"
echo "    a config value, or a time/version-based trigger)."
echo "  - Recursively audit this package's own dependencies (checked THIS"
echo "    package's direct dependency list, not what axios/playwright/etc."
echo "    themselves contain)."
if [ "$OBFUSCATED" -eq 1 ]; then
  echo "  - Meaningfully scan the flagged file(s) above — minified code makes"
    echo "    the eval/exec grep in step 5 unreliable. Score Auditability as"
    echo "    Fail for this component rather than trusting a clean grep result."
fi
echo ""
echo "If the component is NOT npm-distributed (e.g. a hosted URL endpoint"
echo "like some MCP 'quick install' options), this script does not apply at"
echo "all — there is no package to download. Fall back to the manual"
echo "checklist in references/draft-v1-manual-checklist.md and score"
echo "Auditability as Fail by default per the skill's rule on missing evidence."
echo "=================================================="
echo ""
echo "Working files in: $WORKDIR"
echo "Feed this output — including the limitations above — back into the"
echo "5-category scorecard in SKILL.md. The scorecard's COVERAGE LIMITATIONS"
echo "field should be filled in from this block, not omitted."
echo "=================================================="
