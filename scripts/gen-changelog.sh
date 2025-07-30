#!/bin/bash

# Swift SDK Changelog Generator
# Adapted from web-sdk's gen-changelog.mjs

CHANGELOG_FILE="./CHANGELOG.md"
COMMIT_TITLE="chore: release"
BRANCH=${1:-$(git branch --show-current)}

# Get commits since last release tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$LAST_TAG" ]; then
  echo "No previous tags found. Getting all commits..."
  COMMITS=$(git log --oneline --pretty=format:"%s - %h" $BRANCH)
else
  echo "Getting commits since $LAST_TAG..."
  COMMITS=$(git log $LAST_TAG..$BRANCH --oneline --pretty=format:"%s - %h")
fi

# Initialize categories
FEATURES=""
FIXES=""
CHORES=""
DOCS=""
STYLES=""
REFACTORS=""
PERFS=""
TESTS=""

# Parse commits
while IFS= read -r commit; do
  # Skip empty lines
  [ -z "$commit" ] && continue
  
  # Skip release commits
  if [[ $commit =~ $COMMIT_TITLE ]]; then
    continue
  fi
  
  # Extract type and title
  TYPE=$(echo "$commit" | cut -d':' -f1 | tr -d '[:space:]')
  TITLE=$(echo "$commit" | cut -d':' -f2-)
  
  # Skip IGNORE commits
  if [[ $TITLE =~ ^[[:space:]]*IGNORE ]]; then
    continue
  fi
  
  # Check for breaking changes
  if [[ $TYPE == *"!" ]]; then
    TYPE=${TYPE%!}
    TITLE="**BREAKING CHANGE**$TITLE"
  fi
  
  # Categorize commits
  case $TYPE in
    feat)
      FEATURES="${FEATURES}- ${commit}\n"
      ;;
    fix)
      FIXES="${FIXES}- ${commit}\n"
      ;;
    chore)
      CHORES="${CHORES}- ${commit}\n"
      ;;
    docs)
      DOCS="${DOCS}- ${commit}\n"
      ;;
    style)
      STYLES="${STYLES}- ${commit}\n"
      ;;
    refactor)
      REFACTORS="${REFACTORS}- ${commit}\n"
      ;;
    perf)
      PERFS="${PERFS}- ${commit}\n"
      ;;
    test)
      TESTS="${TESTS}- ${commit}\n"
      ;;
    *)
      echo "Unknown commit type: $TYPE, skipping."
      ;;
  esac
done <<< "$COMMITS"

# Use "Unreleased" as version since this is for the NEXT release
VERSION="Unreleased"

# Build changelog entry
NEW_ENTRY="# Release ${VERSION} ($(date '+%a %b %d %Y'))

"

# Add sections if they have content
[ -n "$FEATURES" ] && NEW_ENTRY="${NEW_ENTRY}### Features
${FEATURES}
"
[ -n "$FIXES" ] && NEW_ENTRY="${NEW_ENTRY}### Fixes
${FIXES}
"
[ -n "$CHORES" ] && NEW_ENTRY="${NEW_ENTRY}### Chores
${CHORES}
"
[ -n "$DOCS" ] && NEW_ENTRY="${NEW_ENTRY}### Docs
${DOCS}
"
[ -n "$STYLES" ] && NEW_ENTRY="${NEW_ENTRY}### Styles
${STYLES}
"
[ -n "$REFACTORS" ] && NEW_ENTRY="${NEW_ENTRY}### Refactors
${REFACTORS}
"
[ -n "$PERFS" ] && NEW_ENTRY="${NEW_ENTRY}### Performance
${PERFS}
"
[ -n "$TESTS" ] && NEW_ENTRY="${NEW_ENTRY}### Tests
${TESTS}
"

# Update or create changelog
if [ -f "$CHANGELOG_FILE" ]; then
  # Read existing content
  EXISTING_CONTENT=$(cat "$CHANGELOG_FILE")
  # Write new content followed by existing
  echo -e "${NEW_ENTRY}\n${EXISTING_CONTENT}" > "$CHANGELOG_FILE"
else
  # Create new file
  echo -e "${NEW_ENTRY}" > "$CHANGELOG_FILE"
fi

echo "Changelog generated successfully!"