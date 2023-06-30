#!/bin/bash
# Nextcloud
# A php-fpm container running Nextcloud.
#
# Copyright (c) 2021  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -eu -o pipefail
export LC_ALL=C.UTF-8

[ -v CI_TOOLS ] && [ "$CI_TOOLS" == "SGSGermany" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS' not set or invalid" >&2; exit 1; }

[ -v CI_TOOLS_PATH ] && [ -d "$CI_TOOLS_PATH" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS_PATH' not set or invalid" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

BUILD_INFO=""
if [ $# -gt 0 ] && [[ "$1" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    BUILD_INFO=".${1,,}"
fi

# get latest Nextcloud version
git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

echo + "VERSION=\"\$(sed -ne 's/^ENV NEXTCLOUD_VERSION \(.*\)$/\1/p' $(quote "./vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile"))\"" >&2
VERSION="$(sed -ne 's/^ENV NEXTCLOUD_VERSION \(.*\)$/\1/p' "$BUILD_DIR/vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile" || true)"

if [ -z "$VERSION" ]; then
    echo "Unable to read Nextcloud version from './vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile': Version not found" >&2
    exit 1
elif ! [[ "$VERSION" =~ ^([0-9]+)\.[0-9]+\.[0-9]+([+~-]|$) ]]; then
    echo "Unable to read Nextcloud version from './vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile': '$VERSION' is no valid version" >&2
    exit 1
fi

VERSION_MAJOR="${BASH_REMATCH[1]}"

# build tags
BUILD_INFO="$(date --utc +'%Y%m%d')$BUILD_INFO"

TAGS=(
    "v$VERSION" "v$VERSION-$BUILD_INFO"
    "v$VERSION_MAJOR" "v$VERSION_MAJOR-$BUILD_INFO"
    "latest"
)

printf 'VERSION="%s"\n' "$VERSION"
printf 'TAGS="%s"\n' "${TAGS[*]}"
