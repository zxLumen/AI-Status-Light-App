#!/usr/bin/env bash
# Upload README media to the GitHub Release "assets".
#
# The images/GIFs are deliberately kept out of git (see .gitignore) so clones and
# pulls stay small; they are served from the release instead:
#   https://github.com/<owner>/<repo>/releases/download/assets/<file>
#
# Re-run after regenerating any media (e.g. `make icon`, a new demo GIF):
#   make assets
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${AISTATUS_ASSETS_TAG:-assets}"
FILES=(
  docs/images/demo-full.gif
  docs/images/demo-menu-working.gif
  docs/images/demo-menu-blocked.gif
  docs/images/demo-bubble-question.gif
  docs/images/bubble-success.jpg
  docs/images/menu-idle.jpg
  docs/images/menu-success.jpg
  docs/images/floating-shell.jpg
  docs/images/icon-1024.png
)

missing=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "missing: $f"; missing=1; }
done
if [ "$missing" != 0 ]; then
  echo "→ 先准备好这些文件(如 make icon / 重新生成 demo-full.gif)再执行" >&2
  exit 1
fi

if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --title "Media assets" --latest=false \
    --notes "README 媒体(图片/GIF),托管在 Release,不随 git push/pull。用 make assets 更新。"
fi

gh release upload "$TAG" "${FILES[@]}" --clobber

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "uploaded → https://github.com/$repo/releases/tag/$TAG"
echo "URL 前缀: https://github.com/$repo/releases/download/$TAG/"
