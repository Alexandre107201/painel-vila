-- Conferência de totais e registros por dia/operação contra um relatório autorizado.
-- Setembro/2026: 35481 itens, R$ 470607.76. Não registra confirmação para datas sem fonte.
create table if not exists public.painel_conferencias_diarias(data date not null,operacao text not null,faturamento numeric not null,linhas bigint not null,conferido_em timestamptz not null default now(),primary key(data,operacao));
alter table public.painel_conferencias_diarias enable row level security;
revoke all on public.painel_conferencias_diarias from public,anon,authenticated;
grant select on public.painel_conferencias_diarias to anon,authenticated;
drop policy if exists leitura_conferencia_painel on public.painel_conferencias_diarias;
create policy leitura_conferencia_painel on public.painel_conferencias_diarias for select to anon,authenticated using(true);
CREATE OR REPLACE FUNCTION public.painel_resumo_v1(p_inicio date, p_fim date, p_detalhes boolean DEFAULT false, p_hora_limite time without time zone DEFAULT NULL::time without time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare chave text; op text; b jsonb; resultado jsonb='{}'::jsonb; ps jsonb; hs jsonb; ht jsonb;
begin
  if p_inicio is null or p_fim is null or p_inicio>p_fim or p_fim-p_inicio>3660 then
    raise exception 'Período inválido.';
  end if;
  foreach chave in array array['fit','gourmet','ambas'] loop
    op=case chave when 'fit' then 'vila_fit' when 'gourmet' then 'vila_gourmet' else null end;
    if p_hora_limite is not null then
      select jsonb_build_object(
        'fat',coalesce(sum(valor_total),0),'quantidade',coalesce(sum(quantidade),0),
        'vendas',coalesce(sum(cupons) filter(where cupons is not null),0)
          +count(distinct (operacao,data,coalesce(nr_venda,''))) filter(where cupons is null),
        'linhas',count(*),'horaMaxima',max(hora))
        into b from public.vendas_teknisa
        where data between p_inicio and p_fim and hora<=p_hora_limite and (op is null or operacao=op);
    else
      select jsonb_build_object('fat',coalesce(sum(faturamento),0),'quantidade',coalesce(sum(quantidade),0),
        'vendas',coalesce(sum(vendas),0),'linhas',coalesce(sum(linhas),0),'horaMaxima',max(hora_maxima))
        into b from public.painel_resumos_diarios
        where data between p_inicio and p_fim and (op is null or operacao=op);
      if p_detalhes then
        select coalesce(jsonb_agg(jsonb_build_array(produto,qtd,fat,fracao,ordem) order by ordem),'[]'::jsonb)
          into ps from (
            select p->>0 produto,sum((p->>1)::numeric) qtd,sum((p->>2)::numeric) fat,
              bool_or((p->>3)::boolean) fracao,min((p->>4)::bigint) ordem
            from public.painel_resumos_diarios d cross join lateral jsonb_array_elements(d.produtos) p
            where d.data between p_inicio and p_fim and (op is null or d.operacao=op)
            group by p->>0
          ) x;
        select jsonb_agg(n order by i) into hs from (
          select g.i,coalesce(sum((d.horas->>g.i)::numeric),0) n
          from generate_series(0,15) g(i) left join public.painel_resumos_diarios d
            on d.data between p_inicio and p_fim and (op is null or d.operacao=op)
          group by g.i
        ) x;
        select jsonb_agg(n order by idx) into ht from (
          select g.idx,coalesce(sum((d.horas->>h.i)::numeric),0) n
          from generate_series(0,27) g(idx)
          left join public.painel_resumos_diarios d on d.data between p_inicio and p_fim
            and (op is null or d.operacao=op) and extract(isodow from d.data)::int-1=g.idx%7
          left join generate_series(0,15) h(i) on
            case when h.i<=4 then 0 when h.i<=8 then 1 when h.i<=11 then 2 else 3 end=g.idx/7
          group by g.idx
        ) x;
        b=b||jsonb_build_object('produtos',ps,'horas',hs,'heat',ht);
      end if;
    end if;
    if p_hora_limite is null then
      b=b||jsonb_build_object('conferencia',(select jsonb_build_object(
        'diasConferidos',count(distinct c.data),
        'diasDivergentes',count(distinct c.data) filter(where c.faturamento<>coalesce(d.faturamento,0) or c.linhas<>coalesce(d.linhas,0)),
        'diferenca',coalesce(sum(coalesce(d.faturamento,0)-c.faturamento),0))
        from public.painel_conferencias_diarias c left join public.painel_resumos_diarios d using(data,operacao)
        where c.data between p_inicio and p_fim and (op is null or c.operacao=op)));
    end if;
    resultado=resultado||jsonb_build_object(chave,b);
  end loop;
  return jsonb_build_object('unidades',resultado,'revisoes',
    (select coalesce(jsonb_agg(jsonb_build_array(data,revisao) order by data),'[]'::jsonb)
     from public.painel_revisoes_diarias where data between p_inicio and p_fim));
end $function$
