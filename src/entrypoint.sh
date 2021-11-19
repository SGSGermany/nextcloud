#!/bin/sh
set -e

[ $# -gt 0 ] || set -- php-fpm "$@"
if [ "$1" == "php-fpm" ]; then
    NEXTCLOUD_UPDATE=1 docker-nc-entrypoint "true"

    crond -f -l 7 -L /dev/stdout &
    occ-cron

    exec "$@"
fi

exec "$@"
