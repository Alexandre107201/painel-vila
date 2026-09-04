// ============================================================
// ALERTAS CALCULADOS - substitui o texto fixo antigo
// Cada regra so aparece quando ha dado real que a sustente.
// As regras de CMV ficam prontas e ligam sozinhas quando
// o campo cmv deixar de ser null no banco.
// ============================================================
function renderActions(){
  const d = DATA[state.unit][state.period];
  const nomeUnidade = state.unit==='fit' ? 'Vila Fit'
                    : state.unit==='gourmet' ? 'Vila Gourmet'
                    : 'as duas unidades';
  const pct1 = v => Math.abs(v).toFixed(1).replace('.',',') + '%';
  const acoes = [];

  // --- 1. Queda/alta relevante de faturamento vs periodo anterior
  if(typeof d.deltaFat === 'number' && Number.isFinite(d.deltaFat)){
    if(d.deltaFat <= -15){
      acoes.push({ tag:'urgente', text:
        `Faturamento de <b>${nomeUnidade}</b> caiu <b>${pct1(d.deltaFat)}</b> em relacao ao periodo anterior. Vale checar fluxo, ruptura de estoque ou equipe reduzida.` });
    } else if(d.deltaFat <= -5){
      acoes.push({ tag:'atencao', text:
        `Faturamento <b>${pct1(d.deltaFat)}</b> abaixo do periodo anterior em <b>${nomeUnidade}</b>. Acompanhar se a tendencia se mantem.` });
    } else if(d.deltaFat >= 15){
      acoes.push({ tag:'oportunidade', text:
        `Faturamento <b>${pct1(d.deltaFat)}</b> acima do periodo anterior em <b>${nomeUnidade}</b>. Identificar o que puxou o resultado e repetir.` });
    }
  }

  // --- 2. Itens por ticket abaixo da meta
  if(Number.isFinite(d.itT) && Number.isFinite(d.itMeta) && d.itT > 0 && d.itT < d.itMeta){
    const faltam = (d.itMeta - d.itT).toFixed(2).replace('.',',');
    acoes.push({ tag:'atencao', text:
      `Itens por ticket em <b>${d.itT.toFixed(2).replace('.',',')}</b>, abaixo da meta de ${d.itMeta.toFixed(2).replace('.',',')} (faltam ${faltam}). Treinar sugestao de item adicional no caixa.` });
  }

  // --- 3. Concentracao de fluxo por hora
  if(Array.isArray(d.horas) && d.horas.some(v=>v>0)){
    const total = d.horas.reduce((s,v)=>s+v,0);
    const max = Math.max(...d.horas);
    const idxPico = d.horas.indexOf(max);
    const horaPico = HOURS[idxPico];
    const participacao = total ? (max/total)*100 : 0;
    if(participacao >= 20){
      acoes.push({ tag:'atencao', text:
        `<b>${pct1(participacao)}</b> das vendas se concentram as <b>${horaPico}h</b>. Conferir escala de cozinha e caixa nesse horario.` });
    }
    // Horas operacionais com movimento muito baixo.
    // Em periodo parcial (dia corrente), ignora horas que ainda nao aconteceram.
    let ultimaHoraComDado = -1;
    d.horas.forEach((v,i)=>{ if(v>0) ultimaHoraComDado = i; });
    const parcial = /parcial/i.test(String(d.periodo||''));
    const horasFracas = d.horas
      .map((v,i)=>({v, h:HOURS[i], i}))
      .filter(x=>x.h>=11 && x.h<=20 && total && (x.v/total)*100 < 2
                 && (!parcial || x.i < ultimaHoraComDado));
    if(horasFracas.length >= 2){
      const lista = horasFracas.slice(0,3).map(x=>x.h+'h').join(', ');
      acoes.push({ tag:'oportunidade', text:
        `Movimento muito baixo em <b>${lista}</b>. Janela possivel para promocao dirigida ou ajuste de equipe.` });
    }
  }

  // --- 4. Produtos foco em queda (usa o historico semanal real)
  const foco = window.FOCO_SEMANAL && window.FOCO_SEMANAL[state.unit];
  if(foco && foco.length >= 3 && window.PRODUTOS_FOCO){
    const fechadas = foco.filter(s=>!s.atual);
    if(fechadas.length >= 2){
      const ult = fechadas[fechadas.length-1].valores;
      const pen = fechadas[fechadas.length-2].valores;
      const quedas = window.PRODUTOS_FOCO.map((p,i)=>{
        const a = Number(pen[i]||0), b = Number(ult[i]||0);
        if(!a || a < 5) return null;              // ignora base pequena demais
        const varc = ((b-a)/a)*100;
        return varc <= -20 ? {nome:p.nome, varc} : null;
      }).filter(Boolean).sort((x,y)=>x.varc-y.varc);
      if(quedas.length){
        const nomes = quedas.slice(0,3).map(q=>`<b>${q.nome}</b> (${pct1(q.varc)})`).join(', ');
        acoes.push({ tag:'urgente', text:
          `Produtos foco em queda forte na ultima semana fechada: ${nomes}. Verificar disponibilidade, preco ou exposicao.` });
      }
    }
  }

  // --- 5. Produtos "Dogs" da matriz
  const m = d.matrix || DATA[state.unit].matrix;
  if(m && Array.isArray(m.dogs) && m.dogs.length >= 3){
    acoes.push({ tag:'oportunidade', text:
      `Baixa saida e baixo ticket: ${m.dogs.slice(0,3).map(n=>`<b>${n}</b>`).join(', ')}. Avaliar remocao do mix ou reposicionamento.` });
  }

  // --- 6. CMV (inativo ate existir dado de custo no banco)
  if(Number.isFinite(d.cmv) && Number.isFinite(d.cmvMeta)){
    if(d.cmv > d.cmvMeta){
      const acima = (d.cmv - d.cmvMeta).toFixed(1).replace('.',',');
      acoes.push({ tag:'urgente', text:
        `CMV de <b>${nomeUnidade}</b> em ${d.cmv.toFixed(1).replace('.',',')}% — <b>${acima}pp acima</b> da meta de ${d.cmvMeta}%. Revisar ficha tecnica e custo de compra dos itens de maior saida.` });
    } else if(d.cmv <= d.cmvMeta - 3){
      acoes.push({ tag:'oportunidade', text:
        `CMV em ${d.cmv.toFixed(1).replace('.',',')}%, abaixo da meta. Verificar se ha espaco para melhorar porcionamento ou qualidade sem perder margem.` });
    }
  }

  const lista = document.getElementById('actionsList');
  if(!acoes.length){
    lista.innerHTML = `<li class="action-item">
      <span class="action-text" style="color:var(--text-3)">Nenhum alerta relevante para este periodo. Os indicadores estao dentro do esperado ou ainda nao ha dado suficiente.</span>
    </li>`;
    return;
  }
  lista.innerHTML = acoes.map(a=>`
    <li class="action-item">
      <span class="action-tag ${a.tag}">${a.tag.toUpperCase()}</span>
      <span class="action-text">${a.text}</span>
    </li>`).join('');
}
function renderRunrate(){
  const label = document.querySelector('.runrate-label');
  const elValor = document.getElementById('runrateValue');
  const elBase  = document.getElementById('runrateBasis');
  const elComp  = document.getElementById('runrateCompare');

  // ----- Periodo de mes fechado (Agosto): mostra o realizado -----
  if(state.period === 'agosto'){
    const d = DATA[state.unit].agosto;
    if(label) label.textContent = 'FATURAMENTO DO MES';
    elValor.textContent = fmtR(d.fat);
    elValor.style.color = '';
    elBase.textContent = 'Agosto/2026 - mes fechado';
    const linhas = [];
    if(Number.isFinite(d.deltaMesAnt))
      linhas.push(`<div class="line ${d.deltaMesAnt>=0?'up':'down'}">${d.deltaMesAnt>=0?'+':'-'} ${Math.abs(d.deltaMesAnt).toFixed(1).replace('.',',')}% vs JUL/2026</div>`);
    if(Number.isFinite(d.deltaAnoAnt))
      linhas.push(`<div class="line ${d.deltaAnoAnt>=0?'up':'down'}">${d.deltaAnoAnt>=0?'+':'-'} ${Math.abs(d.deltaAnoAnt).toFixed(1).replace('.',',')}% vs AGO/2025</div>`);
    elComp.innerHTML = linhas.join('');
    return;
  }

  const f = FECHAMENTO[state.unit];
  const dias = Number(f.diasDecorridos) || 0;
  const MIN_DIAS = 5;   // abaixo disso a projecao nao tem valor estatistico

  // ----- Poucos dias: nao projeta, explica o porque -----
  if(dias < MIN_DIAS){
    if(label) label.textContent = 'PROJECAO DE FECHAMENTO';
    elValor.textContent = '—';
    elValor.style.color = 'var(--text-3)';
    elBase.textContent = dias === 0
      ? 'sem dados do mes corrente ainda'
      : `apenas ${dias} ${dias===1?'dia':'dias'} de dados - projecao a partir de ${MIN_DIAS} dias`;
    const linhas = [`<div class="line pending">acumulado ate agora: <b>${fmtR(f.fatAcumulado)}</b></div>`];
    if(f.fatMesAnterior)
      linhas.push(`<div class="line">mesmo periodo do mes anterior: <b>${fmtR(f.fatMesAnterior)}</b></div>`);
    if(Number.isFinite(f.fatAnoAnterior) && f.fatAnoAnterior > 0)
      linhas.push(`<div class="line">${f.anoAnteriorLabel}: <b>${fmtR(f.fatAnoAnterior)}</b></div>`);
    else
      linhas.push(`<div class="line pending">${f.anoAnteriorLabel}: sem historico importado</div>`);
    elComp.innerHTML = linhas.join('');
    return;
  }

  // ----- Dados suficientes: projeta -----
  const projecao = (f.fatAcumulado / dias) * f.diasMes;
  const confiavel = dias >= 10;
  if(label) label.textContent = confiavel ? 'PROJECAO DE FECHAMENTO' : 'PROJECAO PRELIMINAR';
  elValor.textContent = fmtR(projecao);
  elValor.style.color = confiavel ? '' : 'var(--gourmet)';
  elBase.textContent =
    `com base em ${fmtR(f.fatAcumulado)} ate ${f.dataCorte} (${dias}/${f.diasMes} dias)` +
    (confiavel ? '' : ' - poucos dias, tende a oscilar');

  const linhas = [];
  if(f.fatMesAnterior)
    linhas.push(`<div class="line">mesmo periodo do mes anterior: <b>${fmtR(f.fatMesAnterior)}</b></div>`);
  if(Number.isFinite(f.fatAnoAnterior) && f.fatAnoAnterior > 0)
    linhas.push(`<div class="line">${f.anoAnteriorLabel}: <b>${fmtR(f.fatAnoAnterior)}</b></div>`);
  else
    linhas.push(`<div class="line pending">${f.anoAnteriorLabel}: sem historico importado</div>`);
  linhas.push(`<div class="line" style="margin-top:2px">projecao do mes: <b>${fmtR(projecao)}</b></div>`);
  elComp.innerHTML = linhas.join('');
}

// Re-renderiza com as versoes corrigidas assim que o arquivo carrega.
if (typeof renderAll === 'function') { try { renderAll(); } catch(e){} }

// Ativa a instalação do Painel Vila como aplicativo no Android/Chrome.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('./service-worker.js').catch(function (erro) {
      console.error('Falha ao instalar o Painel Vila como aplicativo.', erro);
    });
  });
}
