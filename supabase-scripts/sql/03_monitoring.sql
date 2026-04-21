-- =====================================================================
-- 03_monitoring.sql
-- Checkup régulier du keepalive. À exécuter ponctuellement (hebdo,
-- ou quand tu te demandes si le projet est toujours actif).
-- Aucune modification d'état : requêtes en lecture seule.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Synthèse santé
-- ---------------------------------------------------------------------
select
  count(*)                                 as total_pings,
  min(ping_at)                             as premier_ping,
  max(ping_at)                             as dernier_ping,
  now() - max(ping_at)                     as depuis_dernier_ping,
  case
    when now() - max(ping_at) > interval '5 days'
      then 'ALERTE: > 5 jours, risque de pause imminente'
    when now() - max(ping_at) > interval '3 days'
      then 'A SURVEILLER: > 3 jours'
    else 'OK'
  end                                      as etat
from public._keepalive;

-- ---------------------------------------------------------------------
-- 2. Régularité des 20 derniers pings
--    (écart attendu ~ 2 jours avec le schedule '0 3 */2 * *')
-- ---------------------------------------------------------------------
select
  ping_at,
  ping_at - lag(ping_at) over (order by ping_at) as ecart_avec_precedent
from public._keepalive
order by ping_at desc
limit 20;

-- ---------------------------------------------------------------------
-- 3. Historique pg_cron (succès / échecs)
-- ---------------------------------------------------------------------
select
  jrd.start_time at time zone 'UTC' as run_utc,
  jrd.status,
  jrd.return_message,
  (jrd.end_time - jrd.start_time)   as duree
from cron.job_run_details jrd
join cron.job j on j.jobid = jrd.jobid
where j.jobname = 'keepalive'
order by jrd.start_time desc
limit 20;

-- ---------------------------------------------------------------------
-- 4. Taux de succès pg_cron (sur les 30 derniers runs)
-- ---------------------------------------------------------------------
with derniers_runs as (
  select jrd.status
  from cron.job_run_details jrd
  join cron.job j on j.jobid = jrd.jobid
  where j.jobname = 'keepalive'
  order by jrd.start_time desc
  limit 30
)
select
  count(*)                                              as total_runs,
  count(*) filter (where status = 'succeeded')          as succes,
  count(*) filter (where status = 'failed')             as echecs,
  round(
    100.0 * count(*) filter (where status = 'succeeded') / nullif(count(*), 0),
    1
  )                                                     as pct_succes
from derniers_runs;

-- ---------------------------------------------------------------------
-- 5. Configuration actuelle du job
-- ---------------------------------------------------------------------
select jobid, jobname, schedule, active, command
from cron.job
where jobname = 'keepalive';

-- ---------------------------------------------------------------------
-- 6. Taille de la table keepalive (doit rester petite, ~50 lignes max
--    avec la rétention 90j et un ping tous les 2 jours)
-- ---------------------------------------------------------------------
select
  pg_size_pretty(pg_total_relation_size('public._keepalive')) as taille_totale,
  (select count(*) from public._keepalive)                    as nb_lignes;
