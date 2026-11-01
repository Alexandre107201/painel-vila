DO $do$
DECLARE definicao text;
BEGIN
  IF to_regprocedure('public.robot_replace_historico_vila_v1(date,date,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'A funcao historica ja existe: revisar antes de alterar.';
  END IF;
  SELECT pg_get_functiondef('public.robot_replace_vendas_conferidas_v1(date,date,jsonb)'::regprocedure) INTO definicao;
  definicao := replace(definicao,'public.robot_replace_vendas_conferidas_v1','public.robot_replace_historico_vila_v1');
  definicao := replace(definicao,'sequencia_item integer,','sequencia_item integer, cupons numeric,');
  definicao := replace(definicao,'sequencia_item, desconto','sequencia_item, desconto, cupons');
  definicao := replace(definicao,'coalesce(x.sequencia_item, 1), x.desconto','coalesce(x.sequencia_item, 1), x.desconto, x.cupons');
  definicao := replace(definicao,'  delete from public.vendas_teknisa',
    $guard$
  if p_inicio <> date_trunc('month',p_inicio)::date
    or p_fim <> (p_inicio + interval '1 month - 1 day')::date
    or p_fim >= date_trunc('month',current_date)::date then
    raise exception 'Somente mes historico completo e permitido.';
  end if;
  if (select count(distinct x.operacao) from jsonb_to_recordset(p_linhas) as x(operacao text)) <> 2 then
    raise exception 'As duas operacoes sao obrigatorias.';
  end if;
  if exists (select 1 from jsonb_to_recordset(p_linhas) as x(cupons numeric) where cupons is null) then
    raise exception 'Cupons obrigatorios.';
  end if;
  delete from public.vendas_teknisa$guard$);
  EXECUTE definicao;
END $do$;
REVOKE ALL ON FUNCTION public.robot_replace_historico_vila_v1(date,date,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.robot_replace_historico_vila_v1(date,date,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';