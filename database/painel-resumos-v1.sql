
-- Dashboard Antigo: derived daily summaries. Source sales and existing APIs remain intact.
create schema if not exists painel_cache_private;
revoke all on schema painel_cache_private from public, anon, authenticated;
create sequence painel_cache_private.revisao_seq;
revoke all on sequence painel_cache_private.revisao_seq from public, anon, authenticated;

create table public.painel_resumos_diarios (
  data date not null,
  operacao text not null,
  faturamento numeric not null,
  quantidade numeric not null,
  vendas numeric not null,
  linhas bigint not null,
  hora_maxima time,
  horas jsonb not null,
  produtos jsonb not null,
  primary key(data,operacao)
);
create table public.painel_revisoes_diarias (
  data date primary key,
  revisao bigint not null,
  atualizado_em timestamptz not null default now()
);
alter table public.painel_resumos_diarios enable row level security;
alter table public.painel_revisoes_diarias enable row level security;
-- Matches the existing source policy "leitura publica painel".
create policy painel_resumos_leitura on public.painel_resumos_diarios for select to anon,authenticated using(true);
create policy painel_revisoes_leitura on public.painel_revisoes_diarias for select to anon,authenticated using(true);
revoke all on public.painel_resumos_diarios, public.painel_revisoes_diarias from public,anon,authenticated;
grant select on public.painel_resumos_diarios, public.painel_revisoes_diarias to anon,authenticated,service_role;

-- Internal maintenance only. Definer allows source importers to update derived
-- data without granting clients write access to the summary tables.
create function painel_cache_private.recalcular_dia(p_data date)
returns void language plpgsql security definer set search_path='' as $fn$
begin
  if p_data is null then return; end if;
  perform pg_catalog.pg_advisory_xact_lock(817264,p_data-date '2000-01-01');
  delete from public.painel_resumos_diarios where data=p_data;
  insert into public.painel_resumos_diarios
  with origem as materialized (
    select * from public.vendas_teknisa where data=p_data
  ), totais as (
    select operacao,coalesce(sum(valor_total),0) fat,coalesce(sum(quantidade),0) qtd,
      coalesce(sum(cupons) filter(where cupons is not null),0)
        +count(distinct coalesce(nr_venda,'')) filter(where cupons is null) vendas,
      count(*) linhas,max(hora) hora_maxima
    from origem group by operacao
  ), produtos as (
    select operacao,coalesce(nullif(produto,''),'?') produto,
      coalesce(sum(quantidade),0) qtd,coalesce(sum(valor_total),0) fat,
      bool_or(abs(coalesce(quantidade,0)-round(coalesce(quantidade,0)))>0.000001) fracao,
      min(id) ordem
    from origem group by operacao,coalesce(nullif(produto,''),'?')
  ), ps as (
    select operacao,jsonb_agg(jsonb_build_array(produto,qtd,fat,fracao,ordem) order by ordem) produtos
    from produtos group by operacao
  ), horario as (
    select operacao,extract(hour from hora)::int hora,sum(coalesce(cupons,1)) n
    from origem group by operacao,extract(hour from hora)::int
  ), hs as (
    select t.operacao,jsonb_agg(coalesce(h.n,0) order by g.hora) horas
    from totais t cross join generate_series(6,21) g(hora)
    left join horario h on h.operacao=t.operacao and h.hora=g.hora group by t.operacao
  )
  select p_data,t.operacao,t.fat,t.qtd,t.vendas,t.linhas,t.hora_maxima,hs.horas,ps.produtos
  from totais t join hs using(operacao) join ps using(operacao);
  insert into public.painel_revisoes_diarias(data,revisao,atualizado_em)
    values(p_data,nextval('painel_cache_private.revisao_seq'::regclass),clock_timestamp())
    on conflict(data) do update set revisao=excluded.revisao,atualizado_em=excluded.atualizado_em;
end $fn$;
revoke all on function painel_cache_private.recalcular_dia(date) from public,anon,authenticated;

create function painel_cache_private.vendas_alteradas()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare d date;
begin
  if TG_OP='INSERT' then
    for d in select distinct data from novas order by data loop perform painel_cache_private.recalcular_dia(d); end loop;
  elsif TG_OP='DELETE' then
    for d in select distinct data from antigas order by data loop perform painel_cache_private.recalcular_dia(d); end loop;
  elsif TG_OP='UPDATE' then
    for d in select data from (select data from novas union select data from antigas) x order by data loop perform painel_cache_private.recalcular_dia(d); end loop;
  elsif TG_OP='TRUNCATE' then
    for d in select data from public.painel_revisoes_diarias order by data loop perform painel_cache_private.recalcular_dia(d); end loop;
  end if;
  return null;
end $fn$;
revoke all on function painel_cache_private.vendas_alteradas() from public,anon,authenticated;

create trigger painel_resumo_insert after insert on public.vendas_teknisa referencing new table as novas for each statement execute function painel_cache_private.vendas_alteradas();
create trigger painel_resumo_delete after delete on public.vendas_teknisa referencing old table as antigas for each statement execute function painel_cache_private.vendas_alteradas();
create trigger painel_resumo_update after update on public.vendas_teknisa referencing new table as novas old table as antigas for each statement execute function painel_cache_private.vendas_alteradas();
create trigger painel_resumo_truncate after truncate on public.vendas_teknisa for each statement execute function painel_cache_private.vendas_alteradas();

create function public.painel_resumo_v1(p_inicio date,p_fim date,p_detalhes boolean default false,p_hora_limite time default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $fn$
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
    resultado=resultado||jsonb_build_object(chave,b);
  end loop;
  return jsonb_build_object('unidades',resultado,'revisoes',
    (select coalesce(jsonb_agg(jsonb_build_array(data,revisao) order by data),'[]'::jsonb)
     from public.painel_revisoes_diarias where data between p_inicio and p_fim));
end $fn$;

create function public.painel_versoes_v1()
returns jsonb language sql stable security invoker set search_path='' as $fn$
 select coalesce(jsonb_agg(jsonb_build_array(data,revisao) order by data),'[]'::jsonb)
 from public.painel_revisoes_diarias;
$fn$;


create function public.painel_foco_v1(p_inicio date,p_fim date)
returns jsonb language plpgsql stable security invoker set search_path='' as $fn$
declare resposta jsonb; seg date=date_trunc('week',p_fim::timestamp)::date;
begin
 if p_inicio is null or p_fim is null or p_inicio>p_fim or p_fim-p_inicio>42 then raise exception 'Período semanal inválido.';end if;
 with itens as materialized (
   select d.data,d.operacao,p->>0 produto,(p->>1)::numeric qtd,(p->>2)::numeric fat
   from public.painel_resumos_diarios d cross join lateral jsonb_array_elements(d.produtos) p
   where d.data between p_inicio and p_fim
 ), semanas as (
   select date_trunc('week',data::timestamp)::date semana,operacao,produto,sum(qtd) qtd,sum(fat) fat,false parcial
   from itens group by 1,2,3
   union all
   select seg-7,operacao,produto,sum(qtd),sum(fat),true
   from itens where data between seg-7 and p_fim-7 group by operacao,produto
 )
 select coalesce(jsonb_agg(jsonb_build_array(semana,operacao,produto,qtd,fat,parcial) order by semana,parcial,operacao,produto),'[]'::jsonb)
 into resposta from semanas;
 return jsonb_build_object('linhas',resposta,'revisoes',
   (select coalesce(jsonb_agg(jsonb_build_array(data,revisao) order by data),'[]'::jsonb)
    from public.painel_revisoes_diarias where data between p_inicio and p_fim));
end $fn$;

create function public.painel_comparativos_v1(p_intervalos jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $fn$
declare p jsonb; resposta jsonb='[]'::jsonb;
begin
 if jsonb_typeof(p_intervalos)<>'array' or jsonb_array_length(p_intervalos)>4 then raise exception 'Intervalos inválidos.';end if;
 for p in select value from jsonb_array_elements(p_intervalos) loop
   resposta=resposta||jsonb_build_array(public.painel_resumo_v1((p->>'inicio')::date,(p->>'fim')::date,false,(p->>'hora')::time));
 end loop;
 return resposta;
end $fn$;

revoke all on function public.painel_resumo_v1(date,date,boolean,time),
 public.painel_versoes_v1(), public.painel_foco_v1(date,date),public.painel_comparativos_v1(jsonb)
 from public;
grant execute on function public.painel_resumo_v1(date,date,boolean,time),
 public.painel_versoes_v1(), public.painel_foco_v1(date,date),public.painel_comparativos_v1(jsonb)
 to anon,authenticated,service_role;

-- Protect bootstrap against concurrent imports; release when migration commits.
lock table public.vendas_teknisa in share row exclusive mode;
do $fn$ declare d date; begin
 for d in select distinct data from public.vendas_teknisa order by data loop
   perform painel_cache_private.recalcular_dia(d);
 end loop;
end $fn$;
analyze public.painel_resumos_diarios;
analyze public.painel_revisoes_diarias;
notify pgrst,'reload schema';
