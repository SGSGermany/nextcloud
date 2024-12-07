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

[ -x "$(which jq 2>/dev/null)" ] \
    || { echo "Missing script dependency: jq" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/chkupd.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

TAG="${TAGS%% *}"
BRANCH_TAG="${TAGS##* }"

# get version to build, if necessary
if [ -z "${VERSION:-}" ]; then
    git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

    echo + "VERSION=\"\$(sed -ne 's/^ENV NEXTCLOUD_VERSION \(.*\)$/\1/p' $(quote "./vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile"))\"" >&2
    VERSION="$(sed -ne 's/^ENV NEXTCLOUD_VERSION \(.*\)$/\1/p' "$BUILD_DIR/vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile" || true)"

    if [ -z "$VERSION" ]; then
        echo "Unable to read Nextcloud version from './vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile': Version not found" >&2
        exit 1
    elif ! [[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)([+~-]|$) ]]; then
        echo "Unable to read Nextcloud version from './vendor/$MERGE_IMAGE_BUD_CONTEXT/Dockerfile': '$VERSION' is no valid version" >&2
        exit 1
    fi
fi

# ensure that the version to build wouldn't cause a version downgrade
# Nextcloud specifically disallows downgrades and would otherwise leave a broken install
# for that check to work we inspect the image tagged with the branch (usually 'latest'), not the version
chkupd_no_downgrade() {
    local IMAGE="$1"

    echo + "PREVIOUS_IMAGE_DATA=\"\$(skopeo inspect $(quote "docker://$IMAGE"))\"" >&2
    local PREVIOUS_IMAGE_DATA="$(skopeo inspect "docker://$IMAGE")"

    if [ -z "$PREVIOUS_IMAGE_DATA" ]; then
        echo "Failed to inspect previously built Nextcloud image '$IMAGE':" \
            "\`skopeo inspect\` failed, likely because there was no image with this tag found" >&2
        return 1
    fi

    echo + "PREVIOUS_VERSION=\"\$(jq -r $(quote '.Env[]|split("=")|select(.[0]=="NEXTCLOUD_VERSION")[1]') <<< \"\$PREVIOUS_IMAGE_DATA\")\"" >&2
    local PREVIOUS_VERSION="$(jq -r '.Env[]|split("=")|select(.[0]=="NEXTCLOUD_VERSION")[1]' <<< "$PREVIOUS_IMAGE_DATA")"

    if [ -z "$PREVIOUS_VERSION" ]; then
        echo "Failed to determine previously built Nextcloud version:" \
            "Image environment variable 'NEXTCLOUD_VERSION' not found" >&2
        return 1
    elif ! [[ "$PREVIOUS_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)([+~-]|$) ]]; then
        echo "Failed to determine previously built Nextcloud version:" \
            "Image environment variable 'NEXTCLOUD_VERSION=$PREVIOUS_VERSION' is no valid version" >&2
        return 1
    fi

    echo + "! version_greater $(quote "$PREVIOUS_VERSION") $(quote "$VERSION")" >&2
    if version_greater "$PREVIOUS_VERSION" "$VERSION"; then
        echo "Can't build Nextcloud $VERSION, because the previously built version ($PREVIOUS_VERSION) is higher" >&2
        echo "Nextcloud specifically disallows downgrades" >&2
        return 1
    fi
}

chkupd_no_downgrade "$REGISTRY/$OWNER/$IMAGE:$BRANCH_TAG" || exit 0

# check whether the base image was updated
# also yields to build the image if the Nextcloud version wasn't built before
chkupd_baseimage "$REGISTRY/$OWNER/$IMAGE" "$TAG" || exit 0

# check whether the image is using the Nextcloud version to build
# this usually just catches version suffixes, e.g. '-pl1'
chkupd_image_version "$REGISTRY/$OWNER/$IMAGE:$TAG" "$VERSION" || exit 0
