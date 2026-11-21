-- =============================================================================
-- Nexora PostgreSQL monitoring role (least privilege)
-- -----------------------------------------------------------------------------
-- Run ONCE as a PostgreSQL superuser on the Nexora database server:
--
--     sudo -u postgres psql -d nexora -f postgres-monitor-role.sql
--
-- This creates a login role used ONLY by postgres_exporter. It can read
-- statistics views and settings (via pg_monitor) but cannot read or modify any
-- application data. Change CHANGE_ME_STRONG_PASSWORD before running.
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexora_monitoring') THEN
        CREATE ROLE nexora_monitoring LOGIN PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
    ELSE
        ALTER ROLE nexora_monitoring LOGIN PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
    END IF;
END
$$;

-- Allow network login to the database.
GRANT CONNECT ON DATABASE nexora TO nexora_monitoring;

-- pg_monitor gives read-only access to pg_stat_* views and pg_settings, which is
-- exactly what postgres_exporter's default collectors need. It grants NO write
-- access to application tables.
GRANT pg_monitor TO nexora_monitoring;

-- Optional: only needed if you add custom queries against the public schema.
-- GRANT USAGE ON SCHEMA public TO nexora_monitoring;

-- Verify:
--   \du nexora_monitoring
--   SELECT has_database_privilege('nexora_monitoring', 'nexora', 'CONNECT');  -- t
--   SELECT pg_has_role('nexora_monitoring', 'pg_monitor', 'MEMBER');          -- t