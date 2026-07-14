#!/usr/bin/env bash

set -Eeuo pipefail

echo "[bootstrap] Aguardando PostgreSQL..."

until PGPASSWORD="${POSTGRES_PASSWORD}" \
  psql \
    --host=db \
    --port="${POSTGRES_PORT:-5432}" \
    --username=postgres \
    --dbname=postgres \
    --no-password \
    --command='SELECT 1' >/dev/null 2>&1
do
  sleep 2
done

echo "[bootstrap] PostgreSQL disponível."

export PGPASSWORD="${POSTGRES_PASSWORD}"

psql \
  --host=db \
  --port="${POSTGRES_PORT:-5432}" \
  --username=postgres \
  --dbname=postgres \
  --no-password \
  --set=ON_ERROR_STOP=1 \
  --set=db_password="${POSTGRES_PASSWORD}" <<'SQL'
DO $bootstrap$
DECLARE
  internal_role text;
  internal_roles text[] := ARRAY[
    'postgres',
    'supabase_admin',
    'authenticator',
    'pgbouncer',
    'supabase_auth_admin',
    'supabase_storage_admin',
    'supabase_functions_admin',
    'supabase_read_only_user'
  ];
BEGIN
  FOREACH internal_role IN ARRAY internal_roles LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = internal_role
    ) THEN
      EXECUTE format(
        'ALTER ROLE %I WITH LOGIN PASSWORD %L',
        internal_role,
        :'db_password'
      );

      RAISE NOTICE 'Senha sincronizada para role %', internal_role;
    END IF;
  END LOOP;
END
$bootstrap$;
SQL

if ! psql \
  --host=db \
  --port="${POSTGRES_PORT:-5432}" \
  --username=postgres \
  --dbname=postgres \
  --no-password \
  --tuples-only \
  --no-align \
  --command="SELECT 1 FROM pg_database WHERE datname = '_supabase'" |
  grep -q '^1$'
then
  echo "[bootstrap] Criando banco _supabase..."

  createdb \
    --host=db \
    --port="${POSTGRES_PORT:-5432}" \
    --username=postgres \
    --owner=supabase_admin \
    _supabase
else
  echo "[bootstrap] Banco _supabase já existe."
fi

psql \
  --host=db \
  --port="${POSTGRES_PORT:-5432}" \
  --username=postgres \
  --dbname=_supabase \
  --no-password \
  --set=ON_ERROR_STOP=1 <<'SQL'
GRANT ALL PRIVILEGES ON DATABASE _supabase TO supabase_admin;
SQL

echo "[bootstrap] Validando roles..."

for role in authenticator supabase_auth_admin supabase_storage_admin supabase_admin
do
  if psql \
    --host=db \
    --port="${POSTGRES_PORT:-5432}" \
    --username=postgres \
    --dbname=postgres \
    --no-password \
    --tuples-only \
    --no-align \
    --command="SELECT 1 FROM pg_roles WHERE rolname='${role}'" |
    grep -q '^1$'
  then
    echo "[bootstrap] Role ${role}: OK"
  else
    echo "[bootstrap] ERRO: role ${role} não existe." >&2
    exit 1
  fi
done

echo "[bootstrap] Inicialização interna concluída."