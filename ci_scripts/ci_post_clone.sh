#!/bin/zsh

# Path where Xcode Cloud expects TestFlight notes
TESTFLIGHT_DIR="../TestFlight"
mkdir -p "$TESTFLIGHT_DIR"

# Xcode Cloud performs shallow clones by default.
# Deepen git history to retrieve earlier commits:
git fetch --deepen 10

# Output header + last 5 commit messages (excluding merge commits)
{
    echo "Build: ${CI_BUILD_NUMBER:-Local}"
    echo "Branch: ${CI_BRANCH:-unknown}"
    echo ""
    echo "Recent Changes:"
    git log -5 --no-merges --pretty=format:"• %s"
} > "$TESTFLIGHT_DIR/WhatToTest.en-US.txt"