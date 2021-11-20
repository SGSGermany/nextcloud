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

nextcloud_ls_versions() {
    jq -r --arg "VERSION" "$1" \
        '.Tags[]|select(test("^[0-9]+\\.[0-9]+\\.[0-9]+-fpm-alpine$") and startswith($VERSION + "."))[:-11]' \
        <<<"$MERGING_IMAGE_REPO_TAGS" | sort_semver
}

sort_semver() {
    sed '/-/!{s/$/_/}' | sort -V -r | sed 's/_$//'
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

# pull current image
echo + "IMAGE_ID=\"\$(podman pull $REGISTRY/$OWNER/$IMAGE:${TAGS[0]})\"" >&2
IMAGE_ID="$(podman pull "$REGISTRY/$OWNER/$IMAGE:${TAGS[0]}" || true)"

if [ -z "$IMAGE_ID" ]; then
    echo "Failed to pull image '$REGISTRY/$OWNER/$IMAGE:${TAGS[0]}': No image with this tag found" >&2
    echo "Image rebuild required" >&2
    echo "build"
    exit
fi

# compare base image digests
echo + "BASE_IMAGE=\"\$(podman image inspect --format '{{index .Annotations \"org.opencontainers.image.base.name\"}}' $IMAGE_ID)\"" >&2
BASE_IMAGE="$(podman image inspect --format '{{index .Annotations "org.opencontainers.image.base.name"}}' "$IMAGE_ID")"

echo + "BASE_IMAGE_DIGEST=\"\$(podman image inspect --format '{{index .Annotations \"org.opencontainers.image.base.digest\"}}' $IMAGE_ID)\"" >&2
BASE_IMAGE_DIGEST="$(podman image inspect --format '{{index .Annotations "org.opencontainers.image.base.digest"}}' "$IMAGE_ID")"

echo + "LATEST_BASE_IMAGE_DIGEST=\"\$(skopeo inspect --format '{{.Digest}}' docker://$BASE_IMAGE)\"" >&2
LATEST_BASE_IMAGE_DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://$BASE_IMAGE" || true)"

if [ -z "$LATEST_BASE_IMAGE_DIGEST" ]; then
    echo "Failed to inspect latest base image '$BASE_IMAGE': \`skopeo inspect\` failed, likely there was no image with this tag found" >&2
    echo "Image rebuild required" >&2
    echo "build"
    exit
fi

if [ -z "$BASE_IMAGE_DIGEST" ] || [ "$BASE_IMAGE_DIGEST" != "$LATEST_BASE_IMAGE_DIGEST" ]; then
    echo "Base image digest mismatch, the image's base image '$BASE_IMAGE' is out of date" >&2
    echo "Current base image digest: $BASE_IMAGE_DIGEST" >&2
    echo "Latest base image digest: $LATEST_BASE_IMAGE_DIGEST" >&2
    echo "Image rebuild required" >&2
    echo "build"
    exit
fi

# get current Nextcloud version
echo + "IMAGE_ENV_VARS=\"\$(podman image inspect --format '{{range .Config.Env}}{{printf \"%q\n\" .}}{{end}}' $IMAGE_ID)\"" >&2
IMAGE_ENV_VARS="$(podman image inspect --format '{{range .Config.Env}}{{printf "%q\n" .}}{{end}}' "$IMAGE_ID")"

echo + "NEXTCLOUD_VERSION=\"\$(sed -ne 's/^\"NEXTCLOUD_VERSION=\(.*\)\"\$/\1/p' <<<\"\$IMAGE_ENV_VARS\")\"" >&2
NEXTCLOUD_VERSION="$(sed -ne 's/^"NEXTCLOUD_VERSION=\(.*\)"$/\1/p' <<<"$IMAGE_ENV_VARS")"

if [ -z "$NEXTCLOUD_VERSION" ]; then
    echo "Unable to get current Nextcloud version: The image doesn't set the env variable 'NEXTCLOUD_VERSION'" >&2
    echo "Image rebuild required" >&2
    echo "build"
    exit 1
elif ! [[ "$NEXTCLOUD_VERSION" =~ ^([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unable to get current Nextcloud version: The image's env variable 'NEXTCLOUD_VERSION=\"$NEXTCLOUD_VERSION\"' is no valid version" >&2
    echo "Image rebuild required" >&2
    echo "build"
    exit 1
fi

NEXTCLOUD_VERSION_MAJOR="${BASH_REMATCH[1]}"

# get latest Nextcloud version
echo + "MERGING_IMAGE_REPO_TAGS=\"\$(skopeo list-tags docker://${MERGING_IMAGE%:*})\"" >&2
MERGING_IMAGE_REPO_TAGS="$(skopeo list-tags "docker://${MERGING_IMAGE%:*}" || true)"

if [ -z "$MERGING_IMAGE_REPO_TAGS" ]; then
    echo "Unable to get latest Nextcloud version: \`skopeo list-tags\` failed for repository 'docker://${MERGING_IMAGE%:*}'" >&2
    echo "Image rebuild required" >&2
    echo "build"
    exit 1
fi

echo + "LATEST_NEXTCLOUD_VERSION=\"\$(nextcloud_ls_versions $NEXTCLOUD_VERSION_MAJOR | head -n 1)\"" >&2
LATEST_NEXTCLOUD_VERSION="$(nextcloud_ls_versions "$NEXTCLOUD_VERSION_MAJOR" | head -n 1)"

# compare Nextcloud versions
if [ "$NEXTCLOUD_VERSION" != "$LATEST_NEXTCLOUD_VERSION" ]; then
    echo "Nextcloud is out of date" >&2
    echo "Current version: $NEXTCLOUD_VERSION" >&2
    echo "Latest version: ${LATEST_NEXTCLOUD_VERSION:-unknown}" >&2
    echo "Image rebuild required" >&2
    echo "build"
    exit
fi
