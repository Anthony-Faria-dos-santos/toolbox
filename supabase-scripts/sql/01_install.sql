-- =====================================================================
-- 01_install.sql
-- Installation idempotente du keepalive Supabase (pg_cron).
-- À exécuter une seule fois (ré-exécutable : recrée proprement l'état).
--
-- Cible    : Supabase Cloud, free tier
-- Objectif : empêcher la mise en pause automatique du projet après 7
--            jours d'inactivité, via une activité DB périodique interne.
-- Schéma   : append-only avec rétention 90 jours.
-- Cadence  : 03:00 UTC, un jour sur deux.
--
-- Exécuter de préférence via DataGrip (Session pooler) pour éviter le
-- timeout de 58 s imposé par le SQL Editor Supabase Studio.
-- =====================================================================

-- 1/7 — Extension pg_cron (no-op si déjà activée)
create extension if not exists pg_cron with schema extensions;

-- 2/7 — Nettoyage de tout état antérieur (idempotence stricte)
do $$
begin
  perform cron.unschedule('keepalive');
exception when others then
  null;   -- le job n'existait pas, OK
end $$;

drop function if exists public._keepalive_tick();
drop table    if exists public._keepalive cascade;

-- 3/7 — Table append-only + index + RLS
create table public._keepalive (
  ping_at timestamptz not null default now()
);

create index _keepalive_ping_at_idx
  on public._keepalive (ping_at);

alter table public._keepalive enable row level security;
-- Aucune policy explicite => anon et authenticated sont bloqués au
-- niveau RLS. Seul postgres (sous lequel pg_cron exécute ses jobs)
-- passe outre. La table n'est donc pas accessible via l'API PostgREST.

-- 4/7 — Fonction SECURITY DEFINER (insert + purge > 90 jours)
create function public._keepalive_tick()
returns void
language sql
security definer
set search_path = public
as $$
  insert into public._keepalive (ping_at) values (now());
  delete from public._keepalive where ping_at < now() - interval '90 days';
$$;

-- Durcissement : retire le droit d'exécution à tous les rôles.
-- pg_cron tourne en tant que propriétaire (postgres), il conserve le droit.
revoke execute on function public._keepalive_tick() from public;

-- 5/7 — Test direct de la fonction (validation applicative locale)
select public._keepalive_tick();

select
  count(*)     as total_pings,
  min(ping_at) as premier_ping,
  max(ping_at) as dernier_ping
from public._keepalive;
-- Attendu : total_pings = 1, premier_ping = dernier_ping = now()

-- 6/7 — Programmation du job
select cron.schedule(
  'keepalive',
  '0 3 */2 * *',                                 -- 03:00 UTC, jours pairs
  $$ select public._keepalive_tick(); $$
) as jobid_cree;

-- 7/7 — Configuration finale (à vérifier visuellement)
select jobid, jobname, schedule, active, command
from cron.job
where jobname = 'keepalive';
-- Attendu : une ligne avec active = true
