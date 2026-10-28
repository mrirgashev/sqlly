#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${1:-$ROOT/Sources/SQLCore/Resources/Postgres}"
mkdir -p "$ROOT/.build"
DATA_ROOT="$(mktemp -d "$ROOT/.build/runtime-smoke.XXXXXX")"
SOCKET="$(mktemp -d /tmp/qc-smoke.XXXXXX)"
PASSWORD="$(/usr/bin/uuidgen)$(/usr/bin/uuidgen)"
cleanup() {
  if [[ -f "$DATA_ROOT/data/postmaster.pid" ]]; then
    "$RUNTIME/bin/pg_ctl" -D "$DATA_ROOT/data" -m immediate -w -t 5 stop > "$DATA_ROOT/shutdown.log" 2>&1 || true
  fi
  rm -rf "$DATA_ROOT" "$SOCKET"
}
trap cleanup EXIT
chmod 700 "$DATA_ROOT" "$SOCKET"
printf '%s\n' "$PASSWORD" > "$DATA_ROOT/password"
chmod 600 "$DATA_ROOT/password"
"$RUNTIME/bin/postgres" --version
"$RUNTIME/bin/initdb" -D "$DATA_ROOT/data" -U qc_smoke --pwfile "$DATA_ROOT/password" -A scram-sha-256 --encoding=UTF8 --locale=C > "$DATA_ROOT/initdb.log" 2>&1
rm "$DATA_ROOT/password"
"$RUNTIME/bin/pg_ctl" -D "$DATA_ROOT/data" -l "$DATA_ROOT/server.log" -w -t 15 -o "-k $SOCKET -p 54321 -c listen_addresses='' -c unix_socket_permissions=0700" start > "$DATA_ROOT/start.log" 2>&1
RESULT="$(PGHOST="$SOCKET" PGPORT=54321 PGUSER=qc_smoke PGPASSWORD="$PASSWORD" "$RUNTIME/bin/psql" -X -q -t -A -d postgres -v ON_ERROR_STOP=1 -c 'WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<3) SELECT sum(x)::integer, jsonb_typeof('\''{"offline":true}'\''::jsonb) FROM n;')"
if [[ "$RESULT" != '6|object' ]]; then echo "Packaged runtime query mismatch: $RESULT" >&2; exit 1; fi
echo 'Bundled PostgreSQL relocation smoke passed: initialized cluster, private socket, SCRAM auth, recursive CTE, JSONB, result 6|object.'
