#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# 1. Commit any pending changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "==> Committing pending changes..."
    git add -A
    git commit -m "chore: uncommitted changes before release" || true
fi

# 2. Calculate version from commit count
COMMIT_COUNT=$(git rev-list --count HEAD)
VERSION="1.0.${COMMIT_COUNT}"

echo "==> Version: $VERSION (commits: $COMMIT_COUNT)"

# 3. Update MARKETING_VERSION in pbxproj
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${VERSION};/g" LyricBar.xcodeproj/project.pbxproj

# 4. Commit version bump
git add LyricBar.xcodeproj/project.pbxproj
git commit -m "chore: bump version to ${VERSION}" || true

# 5. Tag
git tag -f "v${VERSION}"

# 6. Push
echo "==> Pushing to origin..."
git push origin main --tags

echo ""
echo "==> Done: v${VERSION} released!"
echo "    Watch: https://github.com/rigelra15/LyricBar/actions"
