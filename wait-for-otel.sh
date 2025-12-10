#!/bin/sh
set -e

host="$1"
port="$2"
shift 2

echo "Waiting for $host:$port to be ready..."

until nc -z "$host" "$port" 2>/dev/null; do
  echo "Waiting for $host:$port..."
  sleep 1
done

echo "$host:$port is ready!"
exec "$@"

