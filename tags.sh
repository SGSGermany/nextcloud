#!/bin/bash
# Nextcloud
# A php-fpm container of Nextcloud.
#
# Copyright (c) 2021  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -eu -o pipefail
export LC_ALL=C

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

if ! podman image exists "$IMAGE:${TAGS%% *}"; then
    echo "Missing built image '"$IMAGE:${TAGS%% *}"': No image with this tag found" >&2
    exit 1
fi

NEXTCLOUD_VERSION="$(podman image inspect --format '{{range .Config.Env}}{{printf "%q\n" .}}{{end}}' "$IMAGE:${TAGS%% *}" \
    | sed -ne 's/^"NEXTCLOUD_VERSION=\(.*\)"$/\1/p')"
if [ -z "$NEXTCLOUD_VERSION" ]; then
    echo "Unable to read image's env variable 'NEXTCLOUD_VERSION': No such variable" >&2
    exit 1
elif ! [[ "$NEXTCLOUD_VERSION" =~ ^([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unable to read image's env variable 'NEXTCLOUD_VERSION': '$NEXTCLOUD_VERSION' is no valid version" >&2
    exit 1
fi

NEXTCLOUD_VERSION_MAJOR="${BASH_REMATCH[1]}"

TAG_DATE="$(date -u +'%Y%m%d%H%M')"

TAGS=(
    "v$NEXTCLOUD_VERSION" "v${NEXTCLOUD_VERSION}_$TAG_DATE"
    "v$NEXTCLOUD_VERSION_MAJOR" "v${NEXTCLOUD_VERSION_MAJOR}_$TAG_DATE"
    "latest"
)

printf 'VERSION="%s"\n' "$NEXTCLOUD_VERSION"
printf 'TAGS="%s"\n' "${TAGS[*]}"
