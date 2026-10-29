#!/bin/bash
# Publish status files from $1 to the ios-status branch (read by the assistant).
SRC="$1"; [ -d "$SRC" ] || exit 0
W="$RUNNER_TEMP/status-repo"; rm -rf "$W"
URL="https://x-access-token:${GITHUB_TOKEN:-$GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git config --global user.name "ios-bot"; git config --global user.email "ios-bot@users.noreply.github.com"
for i in 1 2 3 4 5; do
  rm -rf "$W"
  if git clone -q --depth 1 -b ios-status "$URL" "$W" 2>/dev/null; then :; else
    mkdir -p "$W" && cd "$W" && git init -q && git checkout -q -b ios-status && git remote add origin "$URL"; cd - >/dev/null
  fi
  cp "$SRC"/* "$W"/ 2>/dev/null
  cd "$W" && git add -A && { git commit -qm "status run $GITHUB_RUN_NUMBER" || exit 0; }
  git push -q origin ios-status && { echo "status pushed"; exit 0; }
  cd - >/dev/null; echo "::warning title=status::push failed try $i"; sleep $((i*3))
done
