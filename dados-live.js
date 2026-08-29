(function () {
  var SUPABASE_URL = "https://bbhtrxuaumhpqtbcgewc.supabase.co";
  var SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiaHRyeHVhdW1ocHF0YmNnZXdjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxNzQxMjAsImV4cCI6MjEwMjc1MDEyMH0.9Ea7sTK30uQ3FegcVb1qHmbp3FSkspMd09l0TZicyKY";

  function fmtDataISO(d) {
    return d.toISOString().slice(0, 10);
  }

  function inicioSemana(d) {
    var dia = d.getDay();
    var diff = (dia + 6) % 7;
    var seg = new Date(d);
    seg.setDate(d.getDate() - diff);
    return seg;
  }

  function buscarVendas(dataDe, dataAte) {
    var url = SUPABASE_URL + "/rest/v1/vendas_teknisa?select=*&data=gte." + dataDe + "&data=lte." + dataAte;
    return fetch(url, {
      headers: {
        apikey: SUPABASE_ANON_KEY,
        Authorization: "Bearer " + SUPABASE_ANON_KEY
      }
    }).then(function (resp) {
      if (!resp.ok) throw new Error("Falha ao buscar dados: " + resp.status);
      return resp.json();
    });
  }

  function calcularKpis(linhas) {
    var vendasUnicas = {};
    linhas.forEach(function (l) { vendasUnicas[l.nr_venda] = true; });
    var qtdVendas = Object.keys(vendasUnicas).length || 1;
    var qtdItens = 0, fat = 0;
    linhas.forEach(function (l) {
      qtdItens += Number(l.quantidade || 0);
      fat += Number(l.valor_total || 0);
    });
    return {
      fat: fat,
      itT: qtdItens / qtdVendas,
      tk: fat / qtdVendas,
      deltaFat: null,
      itMeta: 2.0,
      cmv: null, cmvMeta: 35,
      proj: null, projMeta: 0
    };
  }

  function topBottom(linhas) {
    var porProduto = {};
    linhas.forEach(function (l) {
      var nome = l.produto || "?";
      porProduto[nome] = (porProduto[nome] || 0) + Number(l.quantidade || 0);
    });
    var arr = Object.keys(porProduto).map(function (k) { return [k, porProduto[k]]; });
    arr.sort(function (a, b) { return b[1] - a[1]; });
    var top = arr.slice(0, 10);
    var bottom = arr.slice(-10).reverse();
    return { top: top, bottom: bottom };
  }

  function horasArray(linhas) {
    var horas = [];
    for (var i = 0; i < 16; i++) horas.push(0);
    linhas.forEach(function (l) {
      if (!l.hora) return;
      var h = parseInt(String(l.hora).split(":")[0], 10);
      var idx = h - 6;
      if (idx >= 0 && idx < 16) horas[idx] += 1;
    });
    return horas;
  }

  function montarBloco(linhas, periodo) {
    var kpi = calcularKpis(linhas);
    var tb = topBottom(linhas);
    kpi.periodo = periodo;
    kpi.horas = horasArray(linhas);
    kpi.top = tb.top;
    kpi.bottom = tb.bottom;
    return kpi;
  }

  var HEAT_VAZIO = {
    rows: ["Manha (6-10h)", "Almoco (11-14h)", "Tarde (15-17h)", "Noite (18-21h)"],
    cols: ["SEG", "TER", "QUA", "QUI", "SEX", "SAB", "DOM"],
    values: [[0,0,0,0,0,0,0],[0,0,0,0,0,0,0],[0,0,0,0,0,0,0],[0,0,0,0,0,0,0]]
  };
  var MATRIX_VAZIA = { stars: [], plow: [], puzzle: [], dogs: [] };

  function iniciarDadosVivos() {
    var hoje = new Date();
    var hojeISO = fmtDataISO(hoje);
    var seg = inicioSemana(hoje);
    var domPassado = new Date(seg);
    domPassado.setDate(seg.getDate() - 1);
    var segAnterior = new Date(domPassado);
    segAnterior.setDate(domPassado.getDate() - 6);
    var inicioMes = new Date(hoje.getFullYear(), hoje.getMonth(), 1);

    Promise.all([
      buscarVendas(hojeISO, hojeISO),
      buscarVendas(fmtDataISO(segAnterior), fmtDataISO(domPassado)),
      buscarVendas(fmtDataISO(inicioMes), hojeISO)
    ]).then(function (resultados) {
      var linhasHoje = resultados[0];
      var linhasSemana = resultados[1];
      var linhasMes = resultados[2];

      function porOperacao(chave, l) {
        return chave === "ambas" ? true : l.operacao === chave;
      }

      function montarUnidade(chave) {
        var fHoje = linhasHoje.filter(function (l) { return porOperacao(chave, l); });
        var fSemana = linhasSemana.filter(function (l) { return porOperacao(chave, l); });
        var fMes = linhasMes.filter(function (l) { return porOperacao(chave, l); });
        return {
          hoje: montarBloco(fHoje, "Hoje (dados ao vivo)"),
          semana: montarBloco(fSemana, "Semana corrente, seg-hoje (dados ao vivo)"),
          mes: montarBloco(fMes, "Mes corrente (dados ao vivo)"),
          heat: HEAT_VAZIO,
          matrix: MATRIX_VAZIA
        };
      }

      window.DATA = {
        fit: montarUnidade("vila_fit"),
        gourmet: montarUnidade("vila_gourmet"),
        ambas: montarUnidade("ambas")
      };

      var diasDecorridos = hoje.getDate();
      var diasMes = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0).getDate();

      function fatMes(chave) {
        return linhasMes
          .filter(function (l) { return porOperacao(chave, l); })
          .reduce(function (s, l) { return s + Number(l.valor_total || 0); }, 0);
      }

      window.FECHAMENTO = {
        fit: { fatAcumulado: fatMes("vila_fit"), diasDecorridos: diasDecorridos, diasMes: diasMes, dataCorte: hojeISO, fatMesAnterior: null, fatAnoAnterior: 0, anoAnteriorLabel: "ano anterior" },
        gourmet: { fatAcumulado: fatMes("vila_gourmet"), diasDecorridos: diasDecorridos, diasMes: diasMes, dataCorte: hojeISO, fatMesAnterior: null, fatAnoAnterior: 0, anoAnteriorLabel: "ano anterior" },
        ambas: { fatAcumulado: fatMes("ambas"), diasDecorridos: diasDecorridos, diasMes: diasMes, dataCorte: hojeISO, fatMesAnterior: null, fatAnoAnterior: 0, anoAnteriorLabel: "ano anterior" }
      };

      var nota = document.getElementById("dataSourceNote");
      if (nota) nota.textContent = "DADOS AO VIVO - atualizado em " + new Date().toLocaleString("pt-BR");
    }).catch(function (e) {
      console.error("Falha ao carregar dados ao vivo, mantendo dados fixos de exemplo.", e);
    }).then(function () {
      if (window.renderAll) window.renderAll();
    });
  }

  window.iniciarDadosVivos = iniciarDadosVivos;
})();
