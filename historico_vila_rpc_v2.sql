DO $do$
DECLARE definicao text;
BEGIN
  IF to_regprocedure('public.robot_replace_historico_dia_v2(date,date,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'Funcao v2 ja existe; revisar antes de alterar.';
  END IF;
  SELECT pg_get_functiondef('public.robot_replace_historico_vila_v1(date,date,jsonb)'::regprocedure) INTO definicao;
  definicao := replace(definicao,'public.robot_replace_historico_vila_v1','public.robot_replace_historico_dia_v2');
  definicao := replace(definicao,
    $old$if p_inicio <> date_trunc('month',p_inicio)::date
    or p_fim <> (p_inicio + interval '1 month - 1 day')::date
    or p_fim >= date_trunc('month',current_date)::date then
    raise exception 'Somente mes historico completo e permitido.';
  end if;$old$,
    $new$if p_inicio <> p_fim or p_fim >= date_trunc('month',current_date)::date then
    raise exception 'Somente um dia historico por transacao e permitido.';
  end if;$new$);
  definicao := replace(definicao,
    $old$if (select count(distinct x.operacao) from jsonb_to_recordset(p_linhas) as x(operacao text)) <> 2 then
    raise exception 'As duas operacoes sao obrigatorias.';
  end if;$old$,'');
  IF position('Somente um dia historico' in definicao)=0 THEN
    RAISE EXCEPTION 'Guarda diaria nao aplicada.';
  END IF;
  EXECUTE definicao;
END $do$;
REVOKE ALL ON FUNCTION public.robot_replace_historico_dia_v2(date,date,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.robot_replace_historico_dia_v2(date,date,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';