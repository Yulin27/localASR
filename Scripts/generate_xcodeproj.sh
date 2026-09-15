#!/bin/sh
# Generates App/LocalASR.xcodeproj from App/project.yml.
#
# Prerequisites: XcodeGen (MIT), installed with `brew install xcodegen`.
# Usage: Scripts/generate_xcodeproj.sh
#
# The generated project is ignored by git. Rerun this after editing App/project.yml or after
# adding or removing source files.

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
app_dir=$(CDPATH='' cd -- "$script_dir/../App" && pwd)
spec="$app_dir/project.yml"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: XcodeGen is not installed. Install it with: brew install xcodegen" >&2
    exit 1
fi

if [ ! -f "$spec" ]; then
    echo "error: missing project specification at App/project.yml" >&2
    exit 1
fi

if [ ! -f "$app_dir/Config/Local.xcconfig" ]; then
    echo "warning: App/Config/Local.xcconfig is missing, so builds will have no signing team." >&2
    echo "         Copy App/Config/Local.xcconfig.example to App/Config/Local.xcconfig and set DEVELOPMENT_TEAM." >&2
fi

xcodegen generate --spec "$spec" --project "$app_dir"
