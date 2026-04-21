-- =====================================================================
-- 02_test_forced.sql  (v2 — procédure avec COMMIT inline)
-- Test forcé du job pg_cron : auto-calcule la minute cible UTC,
-- reprogramme temporairement, attend, vérifie, puis restaure le
-- schedule de production.
--
-- Durée : 60 à 120 secondes selon l'instant de lancement.
--
-- /!\ À EXECUTER VIA DATAGRIP (ou psql), PAS VIA SUPABASE STUDIO :
--     le SQL Editor Supabase injecte automatiquement
--     `SET statement_timeout='58s'` qui écrase notre set à 5min et
--     tuera le pg_sleep prématurément.
--
-- /!\ POURQUOI UNE PROCEDURE ET PAS UN DO BLOCK :
--     Un DO $$ ... $$ s'exécute dans une seule transaction. Tant
--     qu'elle ne commit pas, le worker pg_cron (qui tourne dans sa
--     propre session) ne voit PAS le nouveau schedule. Résultat :
--     pg_sleep attend pour rien, aucun tick n'est déclenché.
--
--     Une PROCEDURE autorise COMMIT en plein milieu du corps, ce
--     qui rend le alter_job visible au worker AVANT le pg_sleep.
-- =====================================================================

set statement_timeout = '5min';

-- ---------------------------------------------------------------------
-- Procédure de test (recréée à chaque exécution pour rester idempotente)
-- ---------------------------------------------------------------------
create or replace procedure public._keepalive_test_forced()
language plpgsql
as $$
declare
  v_jobid           bigint;
  v_target_time     timestamptz;
  v_target_schedule text;
  v_sleep_seconds   numeric;
  v_runs_before     bigint;
  v_runs_after      bigint;
  v_pings_before    bigint;
  v_pings_after     bigint;
begin
  -- Récupérer le jobid
  select jobid into v_jobid
    from cron.job
   where jobname = 'keepalive';

  if v_jobid is null then
    raise exception 'Job "keepalive" introuvable. Exécuter 01_install.sql d''abord.';
  end if;

  -- Compteurs "avant test"
  select count(*) into v_runs_before
    from cron.job_run_details
   where jobid = v_jobid;

  select count(*) into v_pings_before from public._keepalive;

  -- Cible : début de la 2e minute à venir (marge 60-120 s)
  v_target_time     := date_trunc('minute', now()) + interval '2 minutes';
  v_target_schedule := to_char(v_target_time at time zone 'UTC', 'MI HH24') || ' * * *';

  raise notice '--- REPROGRAMMATION TEMPORAIRE ---';
  raise notice 'Heure cible UTC : %', v_target_time at time zone 'UTC';
  raise notice 'Schedule cron   : %', v_target_schedule;

  perform cron.alter_job(
    job_id   := v_jobid,
    schedule := v_target_schedule
  );

  -- COMMIT CRITIQUE : rend le nouveau schedule visible au worker pg_cron
  commit;

  -- Attendre jusqu'à 20 s après l'heure cible (marge pour le polling du worker)
  v_sleep_seconds := extract(epoch from (v_target_time - now())) + 20;
  raise notice 'Attente : % s', v_sleep_seconds::int;
  perform pg_sleep(v_sleep_seconds);

  -- Restauration schedule de production
  perform cron.alter_job(
    job_id   := v_jobid,
    schedule := '0 3 */2 * *'
  );

  -- Commit de la restauration avant lecture des compteurs (évite
  -- de lire notre propre transaction pour le résultat final)
  commit;

  -- Compteurs "après test"
  select count(*) into v_runs_after
    from cron.job_run_details
   where jobid = v_jobid;

  select count(*) into v_pings_after from public._keepalive;

  raise notice '--- RESULTAT ---';
  raise notice 'Runs pg_cron      avant/après : % / %', v_runs_before, v_runs_after;
  raise notice 'Lignes _keepalive avant/après : % / %', v_pings_before, v_pings_after;

  if v_runs_after > v_runs_before and v_pings_after > v_pings_before then
    raise notice 'SUCCES : pg_cron a déclenché et la fonction a écrit en base';
  elsif v_runs_after > v_runs_before then
    raise warning 'PARTIEL : le run s''est lancé mais la fonction n''a pas écrit. Voir cron.job_run_details.return_message';
  else
    raise warning 'ECHEC : aucun nouveau run détecté. Vérifier que le worker pg_cron est actif.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Lancement du test
-- ---------------------------------------------------------------------
call public._keepalive_test_forced();

reset statement_timeout;

-- ---------------------------------------------------------------------
-- Rapports post-test
-- ---------------------------------------------------------------------

-- Détails des 3 derniers runs
select
  jrd.start_time at time zone 'UTC' as run_utc,
  jrd.status,
  jrd.return_message,
  (jrd.end_time - jrd.start_time)   as duree
from cron.job_run_details jrd
join cron.job j on j.jobid = jrd.jobid
where j.jobname = 'keepalive'
order by jrd.start_time desc
limit 3;

-- État de la table
select count(*) as total_pings, max(ping_at) as dernier_ping
from public._keepalive;

-- Confirmation du schedule de production restauré
select jobname, schedule, active from cron.job where jobname = 'keepalive';
-- Attendu : schedule = '0 3 */2 * *'

-- ---------------------------------------------------------------------
-- Nettoyage : supprimer la procédure de test (optionnel)
-- ---------------------------------------------------------------------
drop procedure if exists public._keepalive_test_forced();