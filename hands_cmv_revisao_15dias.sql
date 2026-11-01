BEGIN;
ALTER POLICY hands_cmv_writer_insert ON public.hands_cmv_captures
WITH CHECK (
 ((select auth.jwt()->'app_metadata'->>'hands_cmv_writer')='true')
 AND (
   competence=date_trunc('month',now() at time zone 'America/Sao_Paulo')::date
   OR (
     competence=(date_trunc('month',now() at time zone 'America/Sao_Paulo')-interval '1 month')::date
     AND extract(day from now() at time zone 'America/Sao_Paulo')<=15
   )
 )
 AND captured_at>=now()-interval '10 minutes'
 AND captured_at<=now()+interval '1 minute'
);
COMMIT;