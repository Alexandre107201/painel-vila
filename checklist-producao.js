/* Checklist operacional de produção: registro local por data, operação e produto.
   Quantidades sugeridas por horário exigem análise histórica horária validada. */
(function(){
'use strict';
const screen=document.getElementById('productionScreen');
if(!screen)return;
const controls=screen.querySelector('.production-controls');
const btn=document.createElement('button');
btn.className='import-secondary';btn.type='button';btn.textContent='Checklist de produção';
controls.appendChild(btn);
const wrap=document.createElement('section');
wrap.id='productionChecklist';
wrap.hidden=true;
wrap.style.cssText='margin:18px 0;padding:16px;background:var(--surface);border:1px solid var(--border);border-radius:12px';
wrap.innerHTML='<h3 style="margin:0 0 8px">Checklist de produção · abertura às 6h e reposições</h3><p class="production-note">Preencha o estoque e confira a previsão na tabela acima. Registre cada lote efetivamente produzido. Os horários e volumes não são calculados automaticamente até a validação da distribuição horária por produto. Os registros desta versão ficam somente neste navegador.</p><div id="pcList"></div><button type="button" class="import-secondary" id="pcExport">Exportar registros (CSV)</button>';
controls.after(wrap);
const date=document.getElementById('productionDate'),unit=document.getElementById('productionUnit'),body=document.getElementById('productionBody');
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','"':'&quot;'}[c]));
const key=()=>['vila-checklist-producao-v1',date.value,unit.value].join(':');
function get(){try{return JSON.parse(localStorage.getItem(key())||'{}')}catch(e){return {}}}
function save(v){try{localStorage.setItem(key(),JSON.stringify(v));return true}catch(e){alert('Não foi possível salvar neste aparelho.');return false}}
function products(){return [...body.querySelectorAll('tr')].map(tr=>tr.querySelector('.focus-name')?.firstChild?.textContent?.trim()).filter(Boolean)}
function draw(){
const saved=get(),items=products();
const forecastByName={};
[...body.querySelectorAll('tr')].forEach(tr=>{const name=tr.querySelector('.focus-name')?.firstChild?.textContent?.trim();const cells=tr.querySelectorAll('td');if(name&&cells.length>=6)forecastByName[name]=cells[5].textContent.trim()});

document.getElementById('pcList').innerHTML=items.length?items.map((name,i)=>{
const rec=saved[name]||{},opening=rec.abertura||{},repl=rec.reposicao||{};
return '<div style="padding:12px 0;border-bottom:1px solid var(--border-soft)" data-name="'+esc(name)+'"><strong>'+esc(name)+'</strong><span class="production-note"> · A produzir conforme dashboard: '+esc(forecastByName[name]||'—')+'</span><div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:8px"><label>6h · quantidade feita<input style="display:block;max-width:115px" type="number" min="0" step="0.01" data-slot="abertura" data-field="quantidade" value="'+esc(opening.quantidade??'')+'"></label><label>6h · responsável<input style="display:block;max-width:160px" data-slot="abertura" data-field="responsavel" value="'+esc(opening.responsavel??'')+'"></label><label>Reposição · horário<input style="display:block" type="time" data-slot="reposicao" data-field="horario" value="'+esc(repl.horario??'')+'"></label><label>Reposição · quantidade<input style="display:block;max-width:115px" type="number" min="0" step="0.01" data-slot="reposicao" data-field="quantidade" value="'+esc(repl.quantidade??'')+'"></label><label>Reposição · responsável<input style="display:block;max-width:160px" data-slot="reposicao" data-field="responsavel" value="'+esc(repl.responsavel??'')+'"></label><label>Sobra / desperdício<input style="display:block;max-width:115px" type="number" min="0" step="0.01" data-field="perda" value="'+esc(rec.perda??'')+'"></label><label>Observação<input style="display:block" data-field="observacao" value="'+esc(rec.observacao??'')+'"></label></div></div>';
}).join(''):'<p>Calcule a produção para carregar os produtos.</p>';
}
btn.onclick=()=>{wrap.hidden=!wrap.hidden;if(!wrap.hidden)draw()};
wrap.addEventListener('change',e=>{const t=e.target,div=t.closest('[data-name]');if(!div||!t.dataset.field)return;const saved=get(),name=div.dataset.name,rec=saved[name]||{},slot=t.dataset.slot,field=t.dataset.field;if(slot){rec[slot]=rec[slot]||{};rec[slot][field]=t.value}else rec[field]=t.value;saved[name]=rec;save(saved)});
document.getElementById('pcExport').onclick=()=>{
const records=get(),lines=[['data','operacao','produto','etapa','horario','quantidade','responsavel','desperdicio','observacao']];
Object.entries(records).forEach(([name,r])=>['abertura','reposicao'].forEach(slot=>{const x=r[slot]||{};lines.push([date.value,unit.value,name,slot,slot==='abertura'?'06:00':x.horario||'',x.quantidade||'',x.responsavel||'',r.perda||'',r.observacao||''])}));
const csv=lines.map(row=>row.map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(';')).join('\r\n'),url=URL.createObjectURL(new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='checklist-producao-'+date.value+'-'+unit.value+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
const observer=new MutationObserver(()=>{if(!wrap.hidden)draw()});observer.observe(body,{childList:true});
date.addEventListener('change',()=>{if(!wrap.hidden)draw()});unit.addEventListener('change',()=>{if(!wrap.hidden)draw()});
const split=document.createElement('section');
split.id='pcSplit';
split.style.cssText='margin:12px 0;padding:12px;border:1px solid #b5c4d0;border-radius:8px';
wrap.insertBefore(split,document.getElementById('pcList'));
const endpoint='https://bbhtrxuaumhpqtbcgewc.supabase.co/rest/v1/vendas_teknisa';
const anon='sb_publishable_VO0CBuxqDHhk3n5IwcFjBA_cDwfq0JK';
let splitRequest=0;
function dayMinus(day,n){const d=new Date(day+'T12:00:00Z');d.setUTCDate(d.getUTCDate()-n);return d.toISOString().slice(0,10)}
function numeric(t){const n=Number(String(t).replace(/\\./g,'').replace(',','.'));return Number.isFinite(n)?n:null}
async function hourlySplit(){
 const request=++splitRequest,day=date.value,op=unit.value;
 if(!/^\\d{4}-\\d{2}-\\d{2}$/.test(day)){split.textContent='Escolha a data.';return}
 split.textContent='Consultando vendas horárias de referência…';
 try{
  const totals=new Map(),dates=[dayMinus(day,1),dayMinus(day,7)];
  for(const refDay of dates){
   const operations=op==='ambas'?['vila_fit','vila_gourmet']:[op==='fit'?'vila_fit':'vila_gourmet'];
   let offset=0;
   while(offset<20000){
    const url=endpoint+'?select=produto,hora,quantidade&data=eq.'+refDay+'&operacao=in.('+operations.join(',')+')&order=id.asc&limit=1000&offset='+offset;
    const response=await fetch(url,{headers:{apikey:anon,Authorization:'Bearer '+anon}});
    if(!response.ok)throw Error('Consulta indisponível ('+response.status+')');
    const page=await response.json();
    for(const item of page){
     const h=parseInt(item.hora,10),q=Number(item.quantidade);
     if(!item.produto||!Number.isFinite(h)||!Number.isFinite(q)||q<=0)continue;
     const x=totals.get(item.produto)||{all:0,morning:0};
     x.all+=q;if(h<11)x.morning+=q;totals.set(item.produto,x);
    }
    offset+=page.length;
    if(page.length<1000)break;
   }
   if(offset>=20000)throw Error('Volume acima do limite de consulta');
  }
  if(request!==splitRequest)return;
  const trs=[...body.querySelectorAll('tr')],lines=[];
  for(const tr of trs){
   const name=tr.querySelector('.focus-name')?.firstChild?.textContent?.trim();
   const cells=tr.querySelectorAll('td');
   if(!name||cells.length<6)continue;
   const ref=totals.get(name),qty=numeric(cells[5].textContent.trim());
   if(!ref||!ref.all||qty===null)continue;
   const pct=ref.morning/ref.all;
   const opening=Math.ceil(qty*pct),later=Math.max(0,qty-opening);
   lines.push('<tr><td>'+esc(name)+'</td><td>'+Math.round(pct*100)+'%</td><td>'+opening+'</td><td>'+later+'</td></tr>');
  }
  split.innerHTML='<strong>Divisão indicativa da previsão do dashboard</strong><p class="production-note">Abertura às 6h = parcela de vendas antes das 11h observada no dia anterior e no mesmo dia da semana anterior. Restante = reposição ao longo do dia. Quantidades são estimativas, não ordens. Conferir estoque, validade, tempo de preparo e sazonalidade antes de produzir.</p>'+(lines.length?'<div style="max-height:320px;overflow:auto"><table class="focus-table"><thead><tr><th>Produto</th><th>Vendas manhã</th><th>Sugestão 6h</th><th>Restante do dia</th></tr></thead><tbody>'+lines.join('')+'</tbody></table></div>':'<p>Sem dados suficientes para dividir a previsão por horário.</p>');
 }catch(e){if(request===splitRequest)split.textContent='Não foi possível estimar a divisão por horário: '+e.message}
}
btn.addEventListener('click',()=>{if(!wrap.hidden)hourlySplit()});
date.addEventListener('change',()=>{if(!wrap.hidden)hourlySplit()});
unit.addEventListener('change',()=>{if(!wrap.hidden)hourlySplit()});

})();
