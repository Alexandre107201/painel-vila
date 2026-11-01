# Instalacao separada: nao altera tarefas ou arquivos dos robos atuais.
$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'CAMERA-PC' -or $env:USERNAME -ne 'CAMERA') {
    throw 'Execute no CAMERA-PC, conectado como CAMERA.'
}
$raiz = 'C:\PainelVilaHistorico'
$conector = 'C:\PainelVilaConnector'
$python = "$conector\.venv\Scripts\python.exe"
$pythonw = "$conector\.venv\Scripts\pythonw.exe"
$nomeTarefa = 'Painel Vila - Historico Ano Anterior'
if (!(Test-Path $python) -or !(Test-Path $pythonw)) { throw 'Python do conector nao encontrado.' }
if (!(Test-Path 'C:\BackupPainelVila\20261101_094312')) { throw 'Backup anterior nao encontrado.' }
if (Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue) {
    throw 'A tarefa historica ja existe. Nao foi substituida. Envie o resultado para conferencia.'
}
Get-ScheduledTask -TaskName 'Painel Vila - Atualizar BI' -ErrorAction Stop | Out-Null
Get-ScheduledTask -TaskName 'Vila-Hands-CMV' -ErrorAction Stop | Out-Null
$arquivosOriginais = Get-ChildItem $conector -File | Where-Object {
    $_.Extension -in '.py', '.bat', '.json' -and $_.Name -ne 'teknisa_session.json'
}
$hashesAntes = @{}
foreach ($arquivo in $arquivosOriginais) {
    $hashesAntes[$arquivo.FullName] = (Get-FileHash $arquivo.FullName -Algorithm SHA256).Hash
}
New-Item -ItemType Directory -Path $raiz -Force | Out-Null
$backupInstalacao = Join-Path $raiz ("backup_instalacao_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backupInstalacao | Out-Null
$xmlAntes = @{}
foreach ($nome in @('Painel Vila - Atualizar BI', 'Vila-Hands-CMV')) {
    $xmlAntes[$nome] = Export-ScheduledTask -TaskName $nome
    [IO.File]::WriteAllText((Join-Path $backupInstalacao ($nome + '.xml')), $xmlAntes[$nome])
}
$codigoPython = @'
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
    corpo = {"p_inicio": inicio.isoformat(), "p_fim": fim.isoformat(), "p_linhas": registros}
    url = cfg["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/robot_replace_historico_vila_v1"
    log("Enviando ambas as operacoes em uma unica transacao.")
    resposta = requests.post(url, headers=headers, json=corpo, timeout=240)
    if resposta.status_code >= 300:
        raise RuntimeError(f"Banco rejeitou importacao: HTTP {resposta.status_code}: {resposta.text[:400]}")
    resultado = resposta.json()
    if int(resultado["itens"]) != len(registros) or Decimal(str(resultado["faturamento"])) != total:
        raise RuntimeError("Confirmacao do banco divergente.")
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
'@
$arquivoPython = Join-Path $raiz 'historico_mensal_vila.py'
if (Test-Path $arquivoPython) {
    Copy-Item $arquivoPython (Join-Path $backupInstalacao 'historico_mensal_vila_anterior.py')
}
[IO.File]::WriteAllText($arquivoPython, $codigoPython, (New-Object System.Text.UTF8Encoding($false)))

Write-Host 'IMPORTANDO NOVEMBRO/2025 COM VALIDACOES. Aguarde...'
& $python -B $arquivoPython --mes 2025-11 --gravar
if ($LASTEXITCODE -ne 0) {
    throw "Teste/importacao nao concluiu. Agendamento NAO criado. Envie o resultado e o log em $raiz\logs\historico.log"
}
foreach ($caminho in $hashesAntes.Keys) {
    if ((Get-FileHash $caminho -Algorithm SHA256).Hash -ne $hashesAntes[$caminho]) {
        throw "Arquivo original mudou durante a instalacao: $caminho. Conferir antes de agendar."
    }
}
foreach ($nome in $xmlAntes.Keys) {
    if ((Export-ScheduledTask -TaskName $nome) -ne $xmlAntes[$nome]) {
        throw "Configuracao da tarefa original mudou: $nome. Conferir antes de agendar."
    }
}
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$proximoMes = (Get-Date -Day 1).Date.AddMonths(1).AddHours(7).AddMinutes(5).ToString('yyyy-MM-ddTHH:mm:ss')
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Historico do mesmo mes do ano anterior. Validacao por quinzenas e gravacao atomica. Requer sessao CAMERA aberta.</Description></RegistrationInfo>
  <Triggers><CalendarTrigger>
    <StartBoundary>$proximoMes</StartBoundary><Enabled>true</Enabled>
    <ScheduleByMonth><DaysOfMonth><Day>1</Day></DaysOfMonth><Months>
      <January/><February/><March/><April/><May/><June/>
      <July/><August/><September/><October/><November/><December/>
    </Months></ScheduleByMonth>
  </CalendarTrigger></Triggers>
  <Principals><Principal id="Autor"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled><Hidden>true</Hidden>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <RestartOnFailure><Interval>PT30M</Interval><Count>3</Count></RestartOnFailure>
  </Settings>
  <Actions Context="Autor"><Exec>
    <Command>$pythonw</Command>
    <Arguments>-B "$arquivoPython" --gravar</Arguments>
    <WorkingDirectory>$raiz</WorkingDirectory>
  </Exec></Actions>
</Task>
"@
Register-ScheduledTask -TaskName $nomeTarefa -Xml $xml -ErrorAction Stop | Out-Null
$novaTarefa = Get-ScheduledTask -TaskName $nomeTarefa
if ($novaTarefa.State -eq 'Disabled' -or $novaTarefa.Actions.Execute -ne $pythonw) {
    throw 'Tarefa criada, mas a verificacao da configuracao falhou.'
}
Write-Host 'CONCLUIDO: novembro/2025 importado e conferido; agendamento mensal criado.'
Write-Host 'Dia 1, 07h05, a partir do proximo mes. Requer CAMERA conectado no Windows; a tela pode ficar bloqueada.'
Write-Host 'Robos de vendas e CMV preservados. Credenciais nao foram copiadas para o novo script.'
Get-ScheduledTaskInfo -TaskName $nomeTarefa |
    Select-Object NextRunTime, LastTaskResult | Format-List
Get-Content (Join-Path $raiz 'logs\historico.log') -Tail 12
