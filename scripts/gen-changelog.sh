#!/bin/bash

# Swift SDK Changelog Generator
# Adapted from web-sdk's gen-changelog.mjs

CHANGELOG_FILE="./CHANGELOG.md"
ALPHA_CHANGELOG_FILE="./ALPHA-CHANGELOG.md"
COMMIT_TITLE="chore: release"
IS_ALPHA=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --alpha)
      IS_ALPHA=true
      shift
      ;;
    *)
      BRANCH="$1"
      shift
      ;;
  esac
done

# Auto-detect branch if not provided
if [[ -z "$BRANCH" ]]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "HEAD" ]]; then
    echo "Error: Cannot determine current branch (detached HEAD?)" >&2
    echo "Please specify branch: ./scripts/gen-changelog.sh <branch-name> [--alpha]" >&2
    exit 1
  fi
  BRANCH="$CURRENT_BRANCH"
fi

# Select changelog file based on alpha flag
if [[ "$IS_ALPHA" == true ]]; then
  CHANGELOG_FILE="$ALPHA_CHANGELOG_FILE"
fi

echo "Generating changelog for branch: $BRANCH"
[[ "$IS_ALPHA" == true ]] && echo "Alpha mode: writing to $ALPHA_CHANGELOG_FILE"

# Get commits since last release tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -z "$LAST_TAG" ]; then
  echo "No previous tags found. Getting all commits..."
  COMMITS=$(git log --oneline --pretty=format:"%s" $BRANCH)
else
  echo "Getting commits since $LAST_TAG..."
  COMMITS=$(git log $LAST_TAG..$BRANCH --oneline --pretty=format:"%s")
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
  TITLE=$(echo "$commit" | cut -d':' -f2- | sed 's/^ *//g')
  
  # Skip IGNORE commits
  if [[ $TITLE =~ ^IGNORE ]]; then
    continue
  fi
  
  # Check for breaking changes
  if [[ $TYPE == *"!" ]]; then
    TYPE=${TYPE%!}
    TITLE="**BREAKING CHANGE** $TITLE"
  fi
  
  # Categorize commits (without hash, matching web-sdk)
  case $TYPE in
    feat)
      FEATURES="${FEATURES}- ${TITLE}\n"
      ;;
    fix)
      FIXES="${FIXES}- ${TITLE}\n"
      ;;
    chore)
      CHORES="${CHORES}- ${TITLE}\n"
      ;;
    docs)
      DOCS="${DOCS}- ${TITLE}\n"
      ;;
    style)
      STYLES="${STYLES}- ${TITLE}\n"
      ;;
    refactor)
      REFACTORS="${REFACTORS}- ${TITLE}\n"
      ;;
    perf)
      PERFS="${PERFS}- ${TITLE}\n"
      ;;
    test)
      TESTS="${TESTS}- ${TITLE}\n"
      ;;
    *)
      echo "Unknown commit type: $TYPE, skipping."
      ;;
  esac
done <<< "$COMMITS"

# Get version from git tag or use placeholder
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "Unreleased")

# Build changelog entry (matching web-sdk format)
NEW_ENTRY="# Release $VERSION ($(date '+%a %b %d %Y'))

## Package Version
- para-swift@$VERSION

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