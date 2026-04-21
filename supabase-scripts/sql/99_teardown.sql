-- =====================================================================
-- 99_teardown.sql
-- Désinstallation complète du keepalive.
--
-- /!\ Destructif : supprime le job, la fonction et la table (historique
--     des pings perdu). L'extension pg_cron est laissée en place
--     (inoffensive et potentiellement utilisée par d'autres jobs).
-- =====================================================================

-- 1/3 — Supprimer le job pg_cron (idempotent)
do $$
begin
  perform cron.unschedule('keepalive');
exception when others then
  null;   -- le job n'existait pas, OK
end $$;

-- 2/3 — Supprimer la fonction
drop function if exists public._keepalive_tick();

-- 3/3 — Supprimer la table (cascade pour les vues/FK éventuelles)
drop table if exists public._keepalive cascade;

-- Vérification : tout doit retourner false / 0
select
  exists (select 1 from cron.job where jobname = 'keepalive') as job_existe_encore,
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = '_keepalive_tick'
  )                                                           as fonction_existe_encore,
  exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = '_keepalive'
  )                                                           as table_existe_encore;
-- Attendu : false / false / false
