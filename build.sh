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
source "$CI_TOOLS_PATH/helper/container.sh.inc"
source "$CI_TOOLS_PATH/helper/container-alpine.sh.inc"
source "$CI_TOOLS_PATH/helper/patch.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

git_clone "$MERGE_IMAGE_GIT_REPO" "$MERGE_IMAGE_GIT_REF" "$BUILD_DIR/vendor" "./vendor"

con_build --tag "$IMAGE-base" \
    --from "$BASE_IMAGE" --check-from "$MERGE_IMAGE_BASE_IMAGE_PATTERN" \
    "$BUILD_DIR/vendor/$MERGE_IMAGE_BUD_CONTEXT" "./vendor/$MERGE_IMAGE_BUD_CONTEXT"

echo + "CONTAINER=\"\$(buildah from $(quote "$IMAGE-base"))\"" >&2
CONTAINER="$(buildah from "$IMAGE-base")"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "mv …/entrypoint.sh …/usr/local/bin/docker-nc-entrypoint" >&2
mv "$MOUNT/entrypoint.sh" "$MOUNT/usr/local/bin/docker-nc-entrypoint"

echo + "rm …/cron.sh" >&2
rm "$MOUNT/cron.sh"

echo + "rm …/etc/php/conf.d/nextcloud.ini" >&2
rm "$MOUNT/etc/php/conf.d/nextcloud.ini"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/" >&2
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

patch_apply "$CONTAINER" "$BUILD_DIR/patch" "./patch"

user_add "$CONTAINER" mysql 65538

cleanup "$CONTAINER"

con_cleanup "$CONTAINER"

cmd buildah config \
    --env "PHP_MEMORY_LIMIT-" \
    --env "PHP_UPLOAD_LIMIT-" \
    --volume "/var/www/html-" \
    "$CONTAINER"

cmd buildah config \
    --volume "/var/www" \
    --volume "/run/mysql" \
    "$CONTAINER"

echo + "NEXTCLOUD_VERSION=\"\$(buildah run $CONTAINER -- /bin/sh -c 'echo \"\$NEXTCLOUD_VERSION\"')\"" >&2
NEXTCLOUD_VERSION="$(buildah run "$CONTAINER" -- /bin/sh -c 'echo "$NEXTCLOUD_VERSION"')"

cmd buildah config \
    --annotation org.opencontainers.image.title="Nextcloud" \
    --annotation org.opencontainers.image.description="A php-fpm container running Nextcloud." \
    --annotation org.opencontainers.image.version="$NEXTCLOUD_VERSION" \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/nextcloud" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="MIT" \
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    --annotation org.opencontainers.image.created="$(date -u +'%+4Y-%m-%dT%H:%M:%SZ')" \
    "$CONTAINER"

con_commit "$CONTAINER" "$IMAGE" "${TAGS[@]}"
