BEGIN;
CREATE FUNCTION hands_cmv_read_private.indicator_for_month(p_competence date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT jsonb_build_object('operation',c.operation,'competence',c.competence,
    'cmv_percent',c.cmv_percent,'captured_at',c.captured_at)
 FROM public.hands_cmv_captures c
 WHERE c.operation='Vila Fit / Vila Gourmet' AND c.competence=p_competence
   AND p_competence=date_trunc('month',p_competence)::date
   AND p_competence<=date_trunc('month',now() at time zone 'America/Sao_Paulo')::date
 ORDER BY c.captured_at DESC,c.received_at DESC,c.id DESC LIMIT 1
$$;
REVOKE ALL ON FUNCTION hands_cmv_read_private.indicator_for_month(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hands_cmv_read_private.indicator_for_month(date) TO anon,authenticated,service_role;
CREATE FUNCTION public.hands_cmv_month_v1(p_competence date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT hands_cmv_read_private.indicator_for_month(p_competence) $$;
REVOKE ALL ON FUNCTION public.hands_cmv_month_v1(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hands_cmv_month_v1(date) TO anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;