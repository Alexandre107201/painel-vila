// Offline PostgreSQL-compatible engine. Usage: node test_sql.mjs /path/to/pglite/dist/index.js
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.argv[2] || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`create role anon; create role authenticated; create schema auth;
create function auth.uid() returns uuid language sql stable as $$select (current_setting('request.jwt.claims',true)::jsonb->>'sub')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select current_setting('request.jwt.claims',true)::jsonb$$;
grant usage on schema auth to authenticated;`);
await db.exec(readFileSync(new URL('../../../sql/hands-cmv-setup.sql',import.meta.url),'utf8'));
async function role(name,claims={}) {await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify(claims)]);await db.exec('set role '+name);}
async function denied(sql){await assert.rejects(()=>db.exec(sql));}
const select='select operation,competence,cmv_percent,captured_at from public.hands_cmv_captures';
const insert=`insert into public.hands_cmv_captures(operation,competence,cmv_percent,merchandise_cost,sales_revenue,captured_at) values ('Vila Fit / Vila Gourmet',date_trunc('month',now() at time zone 'America/Sao_Paulo')::date,47.90,192718.18,402366.40,now())`;
await role('anon');await denied(select);await denied(insert);
await role('authenticated',{sub:'11111111-1111-1111-1111-111111111111'});assert.equal((await db.query(select)).rows.length,0);await denied(insert);
await role('authenticated',{sub:'11111111-1111-1111-1111-111111111111',user_metadata:{hands_cmv_writer:true}});await denied(insert);
await role('authenticated',{sub:'11111111-1111-1111-1111-111111111111',app_metadata:{hands_cmv_writer:true}});
await db.exec(insert);await db.exec(insert);assert.equal((await db.query(select)).rows.length,0);
await denied(insert.replace('47.90','0.00'));await denied(insert.replace('now())',"now()-interval '1 day')"));
await denied(insert.replace("date_trunc('month',now() at time zone 'America/Sao_Paulo')::date","'2020-01-01'::date"));
await denied('update public.hands_cmv_captures set cmv_percent=0');await denied('delete from public.hands_cmv_captures');
await role('authenticated',{sub:'21d9a9d4-022d-4c24-a26a-cc7af788aa2a'});assert.equal((await db.query(select)).rows.length,2);
await denied('select merchandise_cost from public.hands_cmv_captures');await denied(insert);
await db.close();console.log('SQL PASS: schema, anon denied, admin read, writer insert-only, user_metadata denied, amount privacy, invalid data rejected, history preserved');
