#!/usr/bin/env bash
#
# Run the live tests against a throwaway MySQL in Docker.
#
#   scripts/test-live.sh                      # mysql:8.0
#   IMAGE=mysql:8.4 scripts/test-live.sh      # another image
#   scripts/test-live.sh --filter group:live  # extra echoc test arguments
#
# A fresh server has an empty caching_sha2_password cache, so the first login takes the full
# (RSA) authentication path.

set -euo pipefail

IMAGE=${IMAGE:-mysql:8.0}
NAME=libmysql-live-$$
PORT=${PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')}

cd "$(dirname "$0")/.."

docker run -d --rm --name "$NAME" \
    -e MYSQL_ROOT_PASSWORD=rootpw -e MYSQL_DATABASE=shop -e MYSQL_USER=app -e MYSQL_PASSWORD=secret \
    -e MARIADB_ROOT_PASSWORD=rootpw -e MARIADB_DATABASE=shop -e MARIADB_USER=app -e MARIADB_PASSWORD=secret \
    -p "127.0.0.1:$PORT:3306" "$IMAGE" >/dev/null
# -v: the server's data volume goes with it, or every run leaves one behind
trap 'docker rm -f -v "$NAME" >/dev/null 2>&1 || true' EXIT

# the entrypoint starts a temporary server (socket only) to initialise, then the real one: wait
# until a TCP login inside the container works
echo "waiting for $IMAGE on 127.0.0.1:$PORT"
# MariaDB 11 images ship `mariadb`, MySQL images `mysql`
CLIENT=mysql
for _ in $(seq 1 120); do
    if docker exec "$NAME" sh -c 'command -v mysql' >/dev/null 2>&1; then CLIENT=mysql; else CLIENT=mariadb; fi
    if docker exec "$NAME" "$CLIENT" -uroot -prootpw -h127.0.0.1 -e 'SELECT 1' >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
docker exec "$NAME" "$CLIENT" -uroot -prootpw -h127.0.0.1 -e 'SELECT VERSION()' 2>/dev/null

export MYSQL_TEST_URL="mysql://app:secret@127.0.0.1:$PORT/shop"
export MYSQL_ROOT_URL="mysql://root:rootpw@127.0.0.1:$PORT/shop"
echoc test --define mysql --timeout 120000 "$@"
