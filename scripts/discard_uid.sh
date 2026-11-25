git diff --name-only --diff-filter=M -z -- '*.uid' |
    xargs -0 -r git restore --