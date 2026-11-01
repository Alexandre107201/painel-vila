"""Historico mensal separado dos robos existentes. Nenhuma credencial embutida."""
from pathlib import Path
from datetime import datetime, date, timedelta
from decimal import Decimal
from collections import Counter, defaultdict
import argparse
import calendar
import hashlib
import json
import os
import sys
import unicodedata
import time
import requests

BASE = Path(__file__).resolve().parent
CONNECTOR = Path(r"C:\PainelVilaConnector")
sys.path.insert(0, str(CONNECTOR))
import extrair_vendas_painel as robo

def log(mensagem):
    texto = f"{datetime.now().isoformat(timespec='seconds')} | {mensagem}"
    (BASE / "logs").mkdir(exist_ok=True)
    with (BASE / "logs" / "historico.log").open("a", encoding="utf-8") as f:
        f.write(texto + "\n")
    if sys.stdout is not None:
        print(texto, flush=True)

def normalizar(valor):
    return "".join(c for c in unicodedata.normalize("NFKD", str(valor))
                   if not unicodedata.combining(c)).strip().upper()

def numero(valor, campo, vazio=False):
    if valor in (None, ""):
        if vazio:
            return Decimal("0")
        raise ValueError(f"Campo numerico ausente: {campo}")
    n = Decimal(str(valor).replace(",", "."))
    if not n.is_finite():
        raise ValueError(f"Numero invalido: {campo}")
    return n

def data_venda(r):
    valor = str(r.get("DTVENDA") or "").strip()
    for formato in ("%d/%m/%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(valor[:10], formato).date()
        except ValueError:
            pass
    raise ValueError("DTVENDA invalida; nenhum registro sera descartado silenciosamente.")

def identificar(r):
    empresa = str(r.get("CDEMPRESA") or "").strip().zfill(2)
    filial = str(r.get("CDFILIAL") or "").strip().zfill(4)
    loja = normalizar(r.get("NMLOJA") or "")
    regras = {
        ("01", "0001", "VILA GOURMET"): ("vila_gourmet", "0001 - VILA GOURMET"),
        ("02", "0002", "VILA FIT"): ("vila_fit", "0002 - VILA FIT"),
        ("03", "0003", "VILA FIT ALIMENTACAO"): ("vila_fit", "0003 - VILA FIT ALIMENTACAO"),
        ("02", "0002", "VILA GOURMET"): ("vila_gourmet", "0002 - VILA FIT"),
    }
    chave = (empresa, filial, loja)
    if chave not in regras:
        raise ValueError(f"Loja sem mapeamento validado: {chave}. Importacao bloqueada.")
    return regras[chave]

def assinatura(linhas):
    return Counter(json.dumps(r, sort_keys=True, ensure_ascii=True) for r in linhas)

def transformar(linhas, inicio, fim):
    registros = []
    repeticoes = Counter()
    for r in linhas:
        operacao, unidade = identificar(r)
        dia = data_venda(r)
        if not inicio <= dia <= fim:
            raise ValueError("Data fora do periodo contabil solicitado.")
        _, hora = robo.data_hora(r)
        if not hora:
            raise ValueError("Hora da venda invalida.")
        caixa = str(r.get("CDLOJA") or "").strip()
        codigo = str(r.get("CDPRODUTO") or "").strip()
        produto = str(r.get("NMPRODUTO") or "").strip()
        if not caixa or not codigo or not produto:
            raise ValueError("Loja, produto ou codigo ausente.")
        quantidade = numero(r.get("QTDPRODVEND"), "QTDPRODVEND")
        total = numero(r.get("VALORVENDA"), "VALORVENDA")
        cupons = numero(r.get("CUPOM"), "CUPOM")
        desconto = numero(r.get("VRDESCON"), "VRDESCON", vazio=True)
        origem = json.dumps(r, sort_keys=True, ensure_ascii=True)
        repeticoes[origem] += 1
        # Preserva ocorrencias legitimas; nunca remove itens so por terem valores iguais.
        identidade = origem + "|" + str(repeticoes[origem])
        venda = "HIST1-" + hashlib.sha256(identidade.encode()).hexdigest()
        registros.append({
            "operacao": operacao, "unidade": unidade, "caixa": caixa,
            "nr_venda": venda, "data": dia.isoformat(), "hora": hora,
            "produto": produto, "codigo": codigo,
            "quantidade": str(quantidade),
            "valor_unitario": str(total / quantidade if quantidade else Decimal("0")),
            "valor_total": str(total), "cupons": str(cupons),
            "desconto": str(desconto), "sequencia_item": 1,
            "forma_pagamento": r.get("MODALIDADE") or r.get("MODAL"),
        })
    if {r["operacao"] for r in registros} != {"vila_fit", "vila_gourmet"}:
        raise ValueError("Nao foram encontradas as duas operacoes. Gravacao bloqueada.")
    return registros

def esperado(registros):
    resumo = defaultdict(lambda: [0, Decimal("0")])
    for r in registros:
        chave = (r["data"], r["operacao"])
        resumo[chave][0] += 1
        resumo[chave][1] += Decimal(r["valor_total"])
    return dict(resumo)

def verificar_resumos(cfg, headers, inicio, fim, registros):
    url = cfg["SUPABASE_URL"].rstrip("/") + "/rest/v1/painel_resumos_diarios"
    resposta = requests.get(url, headers=headers, params=[
        ("select", "data,operacao,faturamento,linhas"),
        ("data", "gte." + inicio.isoformat()),
        ("data", "lte." + fim.isoformat()),
        ("limit", "1000"),
    ], timeout=120)
    resposta.raise_for_status()
    recebido = {(r["data"], r["operacao"]):
                [int(r["linhas"]), Decimal(str(r["faturamento"]))]
                for r in resposta.json()}
    if recebido != esperado(registros):
        raise RuntimeError("Resumo do dashboard diverge da extracao. Nao marcar como concluido.")
    return recebido

def backup_banco(cfg, headers, inicio, fim, destino):
    url = cfg["SUPABASE_URL"].rstrip("/") + "/rest/v1/vendas_teknisa"
    antigos = []
    ultimo = 0
    while True:
        resposta = requests.get(url, headers=headers, params=[
            ("select", "*"), ("order", "id.asc"), ("limit", "1000"),
            ("id", "gt." + str(ultimo)),
            ("data", "gte." + inicio.isoformat()),
            ("data", "lte." + fim.isoformat()),
        ], timeout=120)
        resposta.raise_for_status()
        pagina = resposta.json()
        if not pagina:
            break
        if int(pagina[-1]["id"]) <= ultimo:
            raise RuntimeError("Paginacao do backup nao avancou.")
        antigos.extend(pagina)
        ultimo = int(pagina[-1]["id"])
    destino.write_text(json.dumps(antigos, ensure_ascii=False), encoding="utf-8")
    log(f"Backup do periodo no banco: {len(antigos)} linhas.")


def gravar_dias(cfg, headers, registros):
    # Transacao atomica por dia: reduz carga e permite repetir sem duplicar.
    dias = defaultdict(list)
    for registro in registros:
        dias[registro["data"]].append(registro)
    url = cfg["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/robot_replace_historico_dia_v2"
    for dia, lote in sorted(dias.items()):
        corpo = {"p_inicio": dia, "p_fim": dia, "p_linhas": lote}
        total_dia = sum((Decimal(r["valor_total"]) for r in lote), Decimal("0"))
        for tentativa in range(1, 4):
            try:
                resposta = requests.post(url, headers=headers, json=corpo, timeout=90)
            except requests.RequestException:
                if tentativa == 3:
                    raise RuntimeError(f"Falha de conexao ao gravar {dia}; consulte o log e repita a rotina.")
                log(f"{dia}: falha de conexao; repeticao segura {tentativa}/3.")
                time.sleep(tentativa * 3)
                continue
            if resposta.status_code in (429, 500, 502, 503, 504, 520, 522, 524):
                if tentativa == 3:
                    raise RuntimeError(f"Falha temporaria persistente em {dia}: HTTP {resposta.status_code}.")
                log(f"{dia}: HTTP {resposta.status_code}; repeticao segura {tentativa}/3.")
                time.sleep(tentativa * 3)
                continue
            if resposta.status_code >= 300:
                raise RuntimeError(f"Banco rejeitou {dia}: HTTP {resposta.status_code}: {resposta.text[:300]}")
            resultado = resposta.json()
            if int(resultado["itens"]) != len(lote) or Decimal(str(resultado["faturamento"])) != total_dia:
                raise RuntimeError(f"Confirmacao divergente no dia {dia}.")
            verificar_resumos(cfg, headers, date.fromisoformat(dia), date.fromisoformat(dia), lote)
            log(f"DIA CONFERIDO {dia}: {len(lote)} linhas; R$ {total_dia:.2f}.")
            break

def executar(mes=None, gravar=False):
    hoje = date.today()
    if mes:
        inicio = datetime.strptime(mes + "-01", "%Y-%m-%d").date()
    else:
        inicio = date(hoje.year - 1, hoje.month, 1)
    fim = date(inicio.year, inicio.month, calendar.monthrange(inicio.year, inicio.month)[1])
    if fim >= hoje.replace(day=1):
        raise ValueError("Somente meses historicos completos sao permitidos.")
    log(f"Inicio {inicio} a {fim}; gravar={gravar}.")
    sessao_cfg = robo.carregar_sessao()
    sessao = robo.criar_sessao(sessao_cfg)

    def buscar(de, ate):
        log(f"Consulta somente leitura {de} a {ate}.")
        # Nunca renova nem altera a sessao compartilhada com o robo de 15 minutos.
        return robo.buscar_vendas(sessao, sessao_cfg,
                                 datetime.combine(de, datetime.min.time()),
                                 datetime.combine(ate, datetime.min.time()))

    mes_inteiro = buscar(inicio, fim)
    meio = inicio.replace(day=15)
    partes = buscar(inicio, meio) + buscar(meio + timedelta(days=1), fim)
    if assinatura(mes_inteiro) != assinatura(partes):
        raise RuntimeError("Mes e quinzenas divergem. Nada sera gravado.")
    registros = transformar(mes_inteiro, inicio, fim)
    if len(registros) != len(mes_inteiro):
        raise RuntimeError("Transformacao perdeu linhas.")
    total = sum((Decimal(r["valor_total"]) for r in registros), Decimal("0"))
    pasta = BASE / "resultados" / (inicio.strftime("%Y-%m") + "_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
    pasta.mkdir(parents=True)
    # Guarda somente o formato do dashboard, sem cookies, tokens ou dados de consumidores.
    (pasta / "extracao_validada.json").write_text(json.dumps(registros, ensure_ascii=False), encoding="utf-8")
    for op in ("vila_fit", "vila_gourmet"):
        itens = [r for r in registros if r["operacao"] == op]
        subtotal = sum((Decimal(r["valor_total"]) for r in itens), Decimal("0"))
        log(f"{op}: {len(itens)} linhas; R$ {subtotal:.2f}.")
    log(f"Mes e quinzenas identicos: {len(registros)} linhas; total R$ {total:.2f}.")
    if not gravar:
        log("TESTE SEM GRAVACAO CONCLUIDO.")
        return
    cfg = robo.carregar_config()
    if cfg["SUPABASE_URL"].rstrip("/") != "https://bbhtrxuaumhpqtbcgewc.supabase.co":
        raise ValueError("Projeto Supabase diferente do validado; gravacao bloqueada.")
    headers = robo.headers_supabase(cfg, "return=representation")
    backup_banco(cfg, headers, inicio, fim, pasta / "backup_banco_antes.json")
    log("Gravacao v2: ambas as operacoes juntas em transacoes por dia.")
    gravar_dias(cfg, headers, registros)
    resumos = verificar_resumos(cfg, headers, inicio, fim, registros)
    relatorio = {
        "periodo_inicio": inicio.isoformat(), "periodo_fim": fim.isoformat(),
        "linhas": len(registros), "total": str(total),
        "mes_igual_quinzenas": True, "resumos_diarios_conferidos": len(resumos),
        "concluido_em": datetime.now().isoformat(), "status": "CONFERIDO",
    }
    (pasta / "resultado.json").write_text(json.dumps(relatorio, indent=2), encoding="utf-8")
    log(f"SUCESSO: {len(registros)} linhas; R$ {total:.2f}; {len(resumos)} resumos diarios conferidos.")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mes")
    parser.add_argument("--gravar", action="store_true")
    args = parser.parse_args()
    BASE.mkdir(parents=True, exist_ok=True)
    import msvcrt
    with (BASE / "execucao.lock").open("a+b") as trava:
        trava.seek(0)
        trava.write(b"0")
        trava.flush()
        trava.seek(0)
        try:
            msvcrt.locking(trava.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise RuntimeError("Outra importacao historica ja esta em andamento.")
        try:
            executar(args.mes, args.gravar)
        finally:
            trava.seek(0)
            msvcrt.locking(trava.fileno(), msvcrt.LK_UNLCK, 1)

if __name__ == "__main__":
    try:
        main()
    except robo.SessaoExpirada:
        log("ERRO: sessao Teknisa expirada. Aguardar renovacao pelo robo atual ou intervencao do responsavel.")
        sys.exit(1)
    except Exception as erro:
        log(f"ERRO: {type(erro).__name__}: {erro}")
        sys.exit(1)

