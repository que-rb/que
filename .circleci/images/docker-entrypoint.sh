#!/usr/bin/env bash
set -e

# if [ "$1" = 'postgres' ]; then
#     chown -R postgres "$PGDATA"

#     if [ -z "$(ls -A "$PGDATA")" ]; then
#         gosu postgres initdb
#     fi

#     exec gosu postgres "$@"
# fi

# exec "$@"

createdb -h localhost -U postgres -p 5432 que-test
createdb -h localhost -U postgres -p 5433 que-test
createdb -h localhost -U postgres -p 5434 que-test

exec gosu postgres "$@"
