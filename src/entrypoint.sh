#!/bin/sh
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

set -e

[ $# -gt 0 ] || set -- php-fpm "$@"
if [ "$1" == "php-fpm" ]; then
    # setup Nextcloud
    NEXTCLOUD_UPDATE=1 docker-nc-entrypoint "true"

    # run crond
    crond -f -l 7 -L /dev/stdout &

    # run Nextcloud's cronjobs once
    occ-cron

    exec "$@"
fi

exec "$@"
