(function () {
    var SUPABASE_URL = "https://bbhtrxuaumhpqtbcgewc.supabase.co";
    var SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiaHRyeHVhdW1ocHF0YmNnZXdjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxNzQxMjAsImV4cCI6MjEwMjc1MDEyMH0.9Ea7sTK30uQ3FegcVb1qHmbp3FSkspMd09l0TZicyKY";

   function iso(d) {
         var y = d.getFullYear();
         var m = String(d.getMonth() + 1).padStart(2, "0");
         var dia = String(d.getDate()).padStart(2, "0");
         return y + "-" + m + "-" + dia;
   }

   function addDias(d, n) {
         var x = new Date(d);
         x.setDate(x.getDate() + n);
         return x;
   }

   function addMeses(d, n) {
         var x = new Date(d);
         x.setMonth(x.getMonth() + n);
         return x;
   }

   function addAnos(d, n) {
         var x = new Date(d);
         x.setFullYear(x.getFullYear() + n);
         return x;
   }

   function inicioSemana(d) {
         var dia = d.getDay();
         var diff = (dia + 6) % 7;
         return addDias(d, -diff);
   }

   function buscar(de, ate) {
         var pagina = 1000;
         function buscarPagina(offset) {
               var url = SUPABASE_URL + "/rest/v1/vendas_teknisa?select=*&data=gte." + de +
                     "&data=lte." + ate + "&order=id.asc&limit=" + pagina + "&offset=" + offset;
               return fetch(url, {
                     headers: {
                           apikey: SUPABASE_ANON_KEY,
                           Authorization: "Bearer " + SUPABASE_ANON_KEY
                     }
               }).then(function (r) {
                     if (!r.ok) throw new Error("HTTP " + r.status);
                     return r.json();
               }).then(function (linhas) {
                     if (linhas.length < pagina) return linhas;
                     return buscarPagina(offset + pagina).then(function (proximas) {
                           return linhas.concat(proximas);
                     });
               });
         }
         return buscarPagina(0).catch(function (e) {
               console.error("Falha na consulta de " + de + " a " + ate + ".", e);
               return [];
         });
   }

   function filtrar(linhas, chave) {
         if (chave === "ambas") return linhas;
         return linhas.filter(function (l) { return l.operacao === chave; });
   }

   function somaFat(linhas) {
         return linhas.reduce(function (s, l) { return s + Number(l.valor_total || 0); }, 0);
   }

   function kpis(linhas) {
         var vendas = {};
         linhas.forEach(function (l) { vendas[l.nr_venda] = true; });
         var qtdVendas = Object.keys(vendas).length;
         var qtdItens = linhas.reduce(function (s, l) { return s + Number(l.quantidade || 0); }, 0);
         var fat = somaFat(linhas);
         return {
                 fat: fat,
                 itT: qtdVendas ? qtdItens / qtdVendas : 0,
                 tk: qtdVendas ? fat / qtdVendas : 0,
                 itMeta: 2.0,
                 cmv: null, cmvMeta: 35,
                 proj: null, projMeta: 0
         };
   }

   function topBottom(linhas) {
         var m = {};
         linhas.forEach(function (l) {
                 var n = l.produto || "?";
                 m[n] = (m[n] || 0) + Number(l.quantidade || 0);
         });
         var arr = Object.keys(m).map(function (k) { return [k, m[k]]; });
         arr.sort(function (a, b) { return b[1] - a[1]; });
         return { top: arr.slice(0, 10), bottom: arr.slice(-10).reverse() };
   }

   function horas(linhas) {
         var h = [];
         for (var i = 0; i < 16; i++) h.push(0);
         linhas.forEach(function (l) {
                 if (!l.hora) return;
                 var hh = parseInt(String(l.hora).split(":")[0], 10);
                 var idx = hh - 6;
                 if (idx >= 0 && idx < 16) h[idx] += 1;
         });
         return h;
   }

   function heat(linhas) {
         var faixas = [[6, 10], [11, 14], [15, 17], [18, 21]];
         var grade = faixas.map(function () { return [0, 0, 0, 0, 0, 0, 0]; });
         linhas.forEach(function (l) {
                 if (!l.hora || !l.data) return;
                 var hh = parseInt(String(l.hora).split(":")[0], 10);
                 var partes = String(l.data).split("-");
                 var dt = new Date(Number(partes[0]), Number(partes[1]) - 1, Number(partes[2]));
                 var col = (dt.getDay() + 6) % 7;
                 for (var i = 0; i < faixas.length; i++) {
                           if (hh >= faixas[i][0] && hh <= faixas[i][1]) { grade[i][col] += 1; break; }
                 }
         });
         var max = 0;
         grade.forEach(function (linha) { linha.forEach(function (v) { if (v > max) max = v; }); });
         var valores = grade.map(function (linha) {
                 return linha.map(function (v) { return max ? Math.round((v / max) * 100) : 0; });
         });
         return {
                 rows: ["Manha (6-10h)", "Almoco (11-14h)", "Tarde (15-17h)", "Noite (18-21h)"],
                 cols: ["SEG", "TER", "QUA", "QUI", "SEX", "SAB", "DOM"],
                 values: valores
         };
   }

   function matriz(linhas) {
         var m = {};
         linhas.forEach(function (l) {
                 var n = l.produto || "?";
                 if (!m[n]) m[n] = { qtd: 0, receita: 0 };
                 m[n].qtd += Number(l.quantidade || 0);
                 m[n].receita += Number(l.valor_total || 0);
         });
         var itens = Object.keys(m).map(function (k) {
                 return { nome: k, qtd: m[k].qtd, preco: m[k].qtd ? m[k].receita / m[k].qtd : 0 };
         });
         if (!itens.length) return { stars: [], plow: [], puzzle: [], dogs: [] };
         var medQtd = itens.reduce(function (s, i) { return s + i.qtd; }, 0) / itens.length;
         var medPreco = itens.reduce(function (s, i) { return s + i.preco; }, 0) / itens.length;
         var out = { stars: [], plow: [], puzzle: [], dogs: [] };
         itens.forEach(function (i) {
                 var pop = i.qtd >= medQtd;
                 var mar = i.preco >= medPreco;
                 if (pop && mar) out.stars.push(i.nome);
                 else if (pop && !mar) out.plow.push(i.nome);
                 else if (!pop && mar) out.puzzle.push(i.nome);
                 else out.dogs.push(i.nome);
         });
         Object.keys(out).forEach(function (k) { out[k] = out[k].slice(0, 4); });
         return out;
   }

   function pct(atual, anterior) {
         if (!anterior) return null;
         return ((atual - anterior) / anterior) * 100;
   }

   function bloco(linhas, periodo, comp) {
         var k = kpis(linhas);
         var tb = topBottom(linhas);
         k.periodo = periodo;
         k.horas = horas(linhas);
         k.top = tb.top;
         k.bottom = tb.bottom;
         k.deltaFat = comp.anterior;
         k.deltaMesAnt = comp.mesAnterior;
         k.deltaAnoAnt = comp.anoAnterior;
         return k;
   }

   function fmtBR(d) { return d.toLocaleDateString("pt-BR"); }

   function iniciarDadosVivos() {
         var hoje = new Date();
         var d0 = iso(hoje);
         var dOntem = iso(addDias(hoje, -1));
         var dMesAnt = iso(addMeses(hoje, -1));
         var dAnoAnt = iso(addAnos(hoje, -1));
         var segAtual = inicioSemana(hoje);
         var sIni = iso(segAtual), sFim = d0;
         var sAntIni = iso(addDias(segAtual, -7)), sAntFim = iso(addDias(segAtual, -1));
         var sMesIni = iso(addMeses(segAtual, -1)), sMesFim = iso(addMeses(hoje, -1));
         var sAnoIni = iso(addAnos(segAtual, -1)), sAnoFim = iso(addAnos(hoje, -1));
         var mIni = iso(new Date(hoje.getFullYear(), hoje.getMonth(), 1)), mFim = d0;
         var mesAntRef = addMeses(hoje, -1);
         var mAntIni = iso(new Date(mesAntRef.getFullYear(), mesAntRef.getMonth(), 1));
         var mAntFim = iso(mesAntRef);
         var anoAntRef = addAnos(hoje, -1);
         var mAnoIni = iso(new Date(anoAntRef.getFullYear(), anoAntRef.getMonth(), 1));
         var mAnoFim = iso(anoAntRef);

      Promise.all([
              buscar(d0, d0), buscar(dOntem, dOntem), buscar(dMesAnt, dMesAnt), buscar(dAnoAnt, dAnoAnt),
              buscar(sIni, sFim), buscar(sAntIni, sAntFim), buscar(sMesIni, sMesFim), buscar(sAnoIni, sAnoFim),
              buscar(mIni, mFim), buscar(mAntIni, mAntFim), buscar(mAnoIni, mAnoFim)
            ]).then(function (r) {
              var dHoje = r[0], dOnt = r[1], dMes = r[2], dAno = r[3];
              var wAtual = r[4], wAnt = r[5], wMes = r[6], wAno = r[7];
              var mAtual = r[8], mAnt = r[9], mAno = r[10];
              var dataExibida = d0;
              var usandoUltimoDia = false;
              if (!dHoje.length && mAtual.length) {
                    dataExibida = mAtual.reduce(function (max, linha) {
                          return String(linha.data) > max ? String(linha.data) : max;
                    }, "");
                    dHoje = mAtual.filter(function (linha) { return String(linha.data) === dataExibida; });
                    usandoUltimoDia = true;
              }
              var partesDataExibida = dataExibida.split("-");
              var dataExibidaObj = new Date(Number(partesDataExibida[0]), Number(partesDataExibida[1]) - 1, Number(partesDataExibida[2]));
              function unidade(chave) {
                        var fHoje = filtrar(dHoje, chave);
                        var fSem = filtrar(wAtual, chave);
                        var fMes = filtrar(mAtual, chave);
                        return {
                                    hoje: bloco(fHoje, usandoUltimoDia
                                          ? "Últimos dados importados - " + fmtBR(dataExibidaObj)
                                          : "Hoje - " + fmtBR(hoje), {
                                                  anterior: pct(somaFat(fHoje), somaFat(filtrar(dOnt, chave))),
                                                  mesAnterior: pct(somaFat(fHoje), somaFat(filtrar(dMes, chave))),
                                                  anoAnterior: pct(somaFat(fHoje), somaFat(filtrar(dAno, chave)))
                                    }),
                                    semana: bloco(fSem, "Semana " + fmtBR(segAtual) + " a " + fmtBR(hoje), {
                                                  anterior: pct(somaFat(fSem), somaFat(filtrar(wAnt, chave))),
                                                  mesAnterior: pct(somaFat(fSem), somaFat(filtrar(wMes, chave))),
                                                  anoAnterior: pct(somaFat(fSem), somaFat(filtrar(wAno, chave)))
                                    }),
                                    mes: bloco(fMes, "Mes corrente ate " + fmtBR(hoje), {
                                                  anterior: pct(somaFat(fMes), somaFat(filtrar(mAnt, chave))),
                                                  mesAnterior: pct(somaFat(fMes), somaFat(filtrar(mAnt, chave))),
                                                  anoAnterior: pct(somaFat(fMes), somaFat(filtrar(mAno, chave)))
                                    }),
                                    heat: heat(fMes),
                                    matrix: matriz(fMes)
                        };
              }

                          window.DATA = {
                                    fit: unidade("vila_fit"),
                                    gourmet: unidade("vila_gourmet"),
                                    ambas: unidade("ambas")
                          };
              var diasDec = hoje.getDate();
              var diasMes = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0).getDate();
              function fech(chave) {
                        return {
                                    fatAcumulado: somaFat(filtrar(mAtual, chave)),
                                    diasDecorridos: diasDec,
                                    diasMes: diasMes,
                                    dataCorte: fmtBR(hoje),
                                    fatMesAnterior: somaFat(filtrar(mAnt, chave)) || null,
                                    fatAnoAnterior: somaFat(filtrar(mAno, chave)),
                                    anoAnteriorLabel: "mesmo periodo " + (hoje.getFullYear() - 1)
                        };
              }
              window.FECHAMENTO = {
                        fit: fech("vila_fit"),
                        gourmet: fech("vila_gourmet"),
                        ambas: fech("ambas")
              };
              var nota = document.getElementById("dataSourceNote");
              if (nota) {
                    nota.textContent = usandoUltimoDia
                          ? "ATENÇÃO: última venda importada em " + fmtBR(dataExibidaObj) + " · dados de hoje ainda não recebidos"
                          : "DADOS AO VIVO · atualizado em " + new Date().toLocaleString("pt-BR");
                    nota.style.color = usandoUltimoDia ? "var(--gourmet)" : "";
              }
      }).catch(function (e) {
              console.error("Falha ao carregar dados ao vivo.", e);
      }).then(function () {
              if (window.renderAll) window.renderAll();
      });
   }

   window.iniciarDadosVivos = iniciarDadosVivos;
})();
