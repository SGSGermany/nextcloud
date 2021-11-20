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

cmd() {
    echo + "$@"
    "$@"
    return $?
}

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$BUILD_DIR/container.env" ] && source "$BUILD_DIR/container.env" \
    || { echo "ERROR: Container environment not found" >&2; exit 1; }

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

# checkout Git repo of the image to merge
echo + "mkdir ./vendor"
mkdir "$BUILD_DIR/vendor"

echo + "git -C ./vendor/ init"
git -C "$BUILD_DIR/vendor/" init

echo + "git -C ./vendor/ remote add origin $MERGING_IMAGE_GIT_REPO"
git -C "$BUILD_DIR/vendor/" remote add "origin" "$MERGING_IMAGE_GIT_REPO"

echo + "MERGING_IMAGE_GIT_COMMIT=\"\$(git -C ./vendor/ ls-remote --refs origin $MERGING_IMAGE_GIT_REF | tail -n 1 | cut -f 1)\""
MERGING_IMAGE_GIT_COMMIT="$(git -C "$BUILD_DIR/vendor/" ls-remote --refs origin "$MERGING_IMAGE_GIT_REF" | tail -n 1 | cut -f 1)"

echo + "git -C ./vendor/ fetch --depth 1 origin $MERGING_IMAGE_GIT_COMMIT"
git -C "$BUILD_DIR/vendor/" fetch --depth 1 origin "$MERGING_IMAGE_GIT_COMMIT"

echo + "git -C ./vendor/ checkout --detach $MERGING_IMAGE_GIT_COMMIT"
git -C "$BUILD_DIR/vendor/" checkout --detach "$MERGING_IMAGE_GIT_COMMIT"

# validate Dockerfile of the image to merge
echo + "[ -f ./vendor/$MERGING_IMAGE_BUD_CONTEXT/Dockerfile ]"
if [ ! -f "$BUILD_DIR/vendor/$MERGING_IMAGE_BUD_CONTEXT/Dockerfile" ]; then
    echo "ERROR: Invalid image to merge: Dockerfile '$BUILD_DIR/vendor/$MERGING_IMAGE_BUD_CONTEXT/Dockerfile' not found" >&2
    exit 1
fi

echo + "MERGING_IMAGE_BASE_IMAGE=\"\$(sed -n -e 's/^FROM\s*\(.*\)$/\1/p' ./vendor/$MERGING_IMAGE_BUD_CONTEXT/Dockerfile)\""
MERGING_IMAGE_BASE_IMAGE="$(sed -n -e 's/^FROM\s*\(.*\)$/\1/p' "$BUILD_DIR/vendor/$MERGING_IMAGE_BUD_CONTEXT/Dockerfile")"

echo + "[[ $MERGING_IMAGE_BASE_IMAGE =~ $MERGING_IMAGE_BASE_IMAGE_REGEX ]]"
if ! [[ "$MERGING_IMAGE_BASE_IMAGE" =~ $MERGING_IMAGE_BASE_IMAGE_REGEX ]]; then
    echo "ERROR: Invalid image to merge: Expecting original base image to match '$MERGING_IMAGE_BASE_IMAGE_REGEX', got '$MERGING_IMAGE_BASE_IMAGE'" >&2
    exit 1
fi

# build image
echo + "buildah bud -t $IMAGE-base --from $BASE_IMAGE ./vendor/$MERGING_IMAGE_BUD_CONTEXT"
buildah bud -t "$IMAGE-base" --from "$BASE_IMAGE" "$BUILD_DIR/vendor/$MERGING_IMAGE_BUD_CONTEXT"

echo + "CONTAINER=\"\$(buildah from $IMAGE-base)\""
CONTAINER="$(buildah from "$IMAGE-base")"

echo + "MOUNT=\"\$(buildah mount $CONTAINER)\""
MOUNT="$(buildah mount "$CONTAINER")"

echo + "mv …/entrypoint.sh …/usr/local/bin/docker-nc-entrypoint"
mv "$MOUNT/entrypoint.sh" "$MOUNT/usr/local/bin/docker-nc-entrypoint"

echo + "rm …/cron.sh"
rm "$MOUNT/cron.sh"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/"
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

cmd buildah run "$CONTAINER" -- \
    adduser -u 65538 -s "/sbin/nologin" -D -h "/" -H mysql

cmd buildah config --volume "/var/www/html-" "$CONTAINER"

cmd buildah config \
    --volume "/var/www" \
    --volume "/run/mysql" \
    "$CONTAINER"

echo + "NEXTCLOUD_VERSION=\"\$(buildah run $CONTAINER -- /bin/sh -c 'echo \"\$NEXTCLOUD_VERSION\"')\""
NEXTCLOUD_VERSION="$(buildah run "$CONTAINER" -- /bin/sh -c 'echo "$NEXTCLOUD_VERSION"')"

cmd buildah config \
    --annotation org.opencontainers.image.title="Nextcloud" \
    --annotation org.opencontainers.image.description="A php-fpm container of Nextcloud." \
    --annotation org.opencontainers.image.version="$NEXTCLOUD_VERSION" \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/nextcloud" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="MIT" \
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    "$CONTAINER"

cmd buildah commit "$CONTAINER" "$IMAGE:${TAGS[0]}"
cmd buildah rm "$CONTAINER"

for TAG in "${TAGS[@]:1}"; do
    cmd buildah tag "$IMAGE:${TAGS[0]}" "$IMAGE:$TAG"
done

