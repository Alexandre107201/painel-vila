-- Verifica arquivo, base e resumo na mesma transação; divergências revertem a importação.
-- painel_conferencias_diarias: escrita apenas pelos dois gestores já autorizados para importar.
CREATE OR REPLACE FUNCTION public.replace_vendas_teknisa_periodo(p_inicio date, p_fim date, p_linhas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '60s'
AS $function$
declare
  v_itens integer;
  v_total numeric;
begin
  if (select auth.uid()) is null or (select auth.uid()) <> all (
    array[
      '21d9a9d4-022d-4c24-a26a-cc7af788aa2a'::uuid,
      '0be7c2a3-0f8f-4538-a476-d9900b4e0f2a'::uuid
    ]
  ) then
    raise exception 'Usuário não autorizado para substituir vendas.';
  end if;

  if p_inicio is null or p_fim is null or p_inicio > p_fim then
    raise exception 'Período de importação inválido.';
  end if;

  select count(*), coalesce(sum(x.valor_total), 0)
    into v_itens, v_total
  from jsonb_to_recordset(p_linhas) as x(
    operacao text,
    unidade text,
    caixa text,
    nr_venda text,
    data date,
    hora time,
    produto text,
    codigo text,
    quantidade numeric,
    valor_unitario numeric,
    valor_total numeric,
    forma_pagamento text,
    sequencia_item integer,
    desconto numeric
  );

  if v_itens = 0 then
    raise exception 'Nenhuma venda válida recebida.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_linhas) as x(data date)
    where x.data < p_inicio or x.data > p_fim
  ) then
    raise exception 'O arquivo contém vendas fora do período informado.';
  end if;

  delete from public.vendas_teknisa
  where data between p_inicio and p_fim;

  insert into public.vendas_teknisa (
    operacao, unidade, caixa, nr_venda, data, hora, produto, codigo,
    quantidade, valor_unitario, valor_total, forma_pagamento,
    sequencia_item, desconto
  )
  select
    x.operacao, x.unidade, x.caixa, x.nr_venda, x.data, x.hora, x.produto,
    x.codigo, x.quantidade, x.valor_unitario, x.valor_total,
    x.forma_pagamento, coalesce(x.sequencia_item, 1), x.desconto
  from jsonb_to_recordset(p_linhas) as x(
    operacao text,
    unidade text,
    caixa text,
    nr_venda text,
    data date,
    hora time,
    produto text,
    codigo text,
    quantidade numeric,
    valor_unitario numeric,
    valor_total numeric,
    forma_pagamento text,
    sequencia_item integer,
    desconto numeric
  );

  if (select count(*) from public.vendas_teknisa where data between p_inicio and p_fim)<>v_itens
     or (select coalesce(sum(valor_total),0) from public.vendas_teknisa where data between p_inicio and p_fim)<>v_total
     or (select coalesce(sum(faturamento),0) from public.painel_resumos_diarios where data between p_inicio and p_fim)<>v_total then
    raise exception 'Importação divergente: registros, faturamento ou resumo não coincidem. Operação cancelada.';
  end if;
  delete from public.painel_conferencias_diarias where data between p_inicio and p_fim;
  insert into public.painel_conferencias_diarias(data,operacao,faturamento,linhas)
  select data,operacao,sum(valor_total),count(*) from public.vendas_teknisa
  where data between p_inicio and p_fim group by data,operacao;
  return jsonb_build_object('itens', v_itens, 'faturamento', v_total);
end;
$function$
