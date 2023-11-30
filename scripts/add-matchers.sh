#!/usr/bin/env bash

if [ -s "$GITHUB_ACTION_PATH/reporter.json" ]; then
  echo "::add-matcher::$GITHUB_ACTION_PATH/reporter.json"
fi

for directory in . .github/actions/$(basename $GITHUB_ACTION_PATH) .github/actions/build-actions; do
  if [ -s "$directory/reporter.json" ]; then
    echo "::add-matcher::$directory/reporter.json"
    break
  fi
done
