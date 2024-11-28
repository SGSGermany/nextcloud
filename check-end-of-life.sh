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

[ -x "$(which skopeo 2>/dev/null)" ] \
    || { echo "Missing script dependency: skopeo" >&2; exit 1; }

[ -x "$(which skopeo 2>/dev/null)" ] \
    || { echo "Missing script dependency: jq" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/chkeol-api.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

if [ -z "${MILESTONE:-}" ]; then
    echo "Missing required environment variable 'MILESTONE'" >&2
    exit 1
fi

if [ -z "${VERSION:-}" ]; then
    echo "Missing required environment variable 'VERSION'" >&2
    exit 1
fi

if [ "$VERSION" != "$MILESTONE" ] && [[ "$VERSION" != "$MILESTONE".* ]]; then
    echo "Invalid build environment: Invalid environment variable 'MILESTONE':" \
        "Version '$VERSION' is no part of the '$MILESTONE' branch" >&2
    exit 1
fi

TAG="${TAGS##* }"

# Nextcloud specifically disallows downgrades, thus bail if this version would require a downgrade
version_greater() {
    [ "$(printf '%s\n' "$@" | sort_semver | tail -n 1)" != "$1" ]
}

echo + "PREVIOUS_IMAGE_DATA=\"\$(skopeo inspect $(quote "docker://$REGISTRY/$OWNER/$IMAGE:$TAG"))\"" >&2
PREVIOUS_IMAGE_DATA="$(skopeo inspect "docker://$REGISTRY/$OWNER/$IMAGE:$TAG")"

if [ -z "$PREVIOUS_IMAGE_DATA" ]; then
    echo "Failed to inspect previously built Nextcloud image '$REGISTRY/$OWNER/$IMAGE:$TAG':" \
        "\`skopeo inspect\` failed, likely there was no image with this tag found" >&2
    exit 1
fi

echo + "PREVIOUS_VERSION=\"\$(jq -r $(quote '.Env[]|split("=")|select(.[0]=="NEXTCLOUD_VERSION")[1]') <<< \"\$PREVIOUS_IMAGE_DATA\")\"" >&2
PREVIOUS_VERSION="$(jq -r '.Env[]|split("=")|select(.[0]=="NEXTCLOUD_VERSION")[1]' <<< "$PREVIOUS_IMAGE_DATA")"

if [ -z "$PREVIOUS_VERSION" ]; then
    echo "Failed to determine previously built Nextcloud version:" \
        "Image environment variable 'NEXTCLOUD_VERSION' not found" >&2
    exit 1
elif ! [[ "$PREVIOUS_VERSION" =~ ^([0-9]+)\.[0-9]+\.[0-9]+([+~-]|$) ]]; then
    echo "Failed to determine previously built Nextcloud version:" \
        "Image environment variable 'NEXTCLOUD_VERSION=$PREVSIOU_VERSION' is no valid version" >&2
    exit 1
fi

echo + "! version_greater $(quote "$PREVIOUS_VERSION") $(quote "$VERSION")" >&2
if version_greater "$PREVIOUS_VERSION" "$VERSION"; then
    echo "Can't build Nextcloud $VERSION, because the previously built version ($PREVIOUS_VERSION) is higher"
    echo "Nextcloud specifically disallows downgrades"
    exit 1
elif [ "$PREVIOUS_VERSION" == "$VERSION" ]; then
    echo "Rebuilding Nextcloud $VERSION"
else
    echo "Upgrading Nextcloud $PREVIOUS_VERSION to $VERSION"
fi

# check support using endoflife.date API
chkeol_api "Nextcloud" "$MILESTONE"
