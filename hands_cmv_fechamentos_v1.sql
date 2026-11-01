BEGIN;
-- Antes: o escritor aceitava apenas a competencia do mes atual.
-- Mantem a mesma identidade autorizada e a janela de dez minutos da captura.
ALTER POLICY hands_cmv_writer_insert ON public.hands_cmv_captures
WITH CHECK (
 ((select auth.jwt()->'app_metadata'->>'hands_cmv_writer')='true')
 AND competence >= date '2026-10-01'
 AND competence <= date_trunc('month',now() at time zone 'America/Sao_Paulo')::date
 AND captured_at >= now()-interval '10 minutes'
 AND captured_at <= now()+interval '1 minute'
);

CREATE SCHEMA hands_cmv_read_private;
REVOKE ALL ON SCHEMA hands_cmv_read_private FROM PUBLIC;
GRANT USAGE ON SCHEMA hands_cmv_read_private TO anon,authenticated,service_role;
-- API publica intencional, limitada a um indicador. Nao retorna custos ou receitas.
CREATE FUNCTION hands_cmv_read_private.latest_indicator()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT jsonb_build_object('operation',c.operation,'competence',c.competence,
    'cmv_percent',c.cmv_percent,'captured_at',c.captured_at)
 FROM public.hands_cmv_captures c
 WHERE c.operation='Vila Fit / Vila Gourmet'
   AND c.competence<=date_trunc('month',now() at time zone 'America/Sao_Paulo')::date
 ORDER BY c.competence DESC,c.captured_at DESC,c.received_at DESC,c.id DESC
 LIMIT 1
$$;
REVOKE ALL ON FUNCTION hands_cmv_read_private.latest_indicator() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hands_cmv_read_private.latest_indicator() TO anon,authenticated,service_role;
CREATE FUNCTION public.hands_cmv_latest_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT hands_cmv_read_private.latest_indicator() $$;
REVOKE ALL ON FUNCTION public.hands_cmv_latest_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hands_cmv_latest_v1() TO anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;