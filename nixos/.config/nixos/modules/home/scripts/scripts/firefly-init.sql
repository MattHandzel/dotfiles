DO
$do$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'firefly') THEN
      CREATE ROLE firefly LOGIN PASSWORD 'supersecretpassword';
   END IF;
END
$do$;

DO
$do$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'firefly') THEN
      CREATE DATABASE firefly OWNER firefly;
   END IF;
END
$do$;

