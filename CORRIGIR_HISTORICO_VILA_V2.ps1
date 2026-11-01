$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'CAMERA-PC' -or $env:USERNAME -ne 'CAMERA') {
    throw 'Execute no CAMERA-PC, como CAMERA.'
}
$tarefa = 'Painel Vila - Historico Ano Anterior'
$raiz = 'C:\PainelVilaHistorico'
$destino = Join-Path $raiz 'historico_mensal_vila.py'
$estado = Get-ScheduledTask -TaskName $tarefa -ErrorAction Stop
if ($estado.State -eq 'Running') { throw 'Historico em execucao; aguarde terminar antes de instalar a correcao.' }
if (!(Test-Path $destino)) { throw 'Instalacao anterior nao encontrada.' }
$originaisAntes = @{}
foreach ($nome in @('Painel Vila - Atualizar BI', 'Vila-Hands-CMV')) {
    $originaisAntes[$nome] = Export-ScheduledTask -TaskName $nome
}
$backup = Join-Path $raiz ('backup_correcao_v2_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item $destino (Join-Path $backup 'historico_mensal_vila_v1.py')
Export-ScheduledTask -TaskName $tarefa |
    Set-Content (Join-Path $backup 'tarefa_historico.xml') -Encoding Unicode
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$novo = Join-Path $raiz 'historico_mensal_vila.py.novo'
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/Alexandre107201/painel-vila/d370066bcafe42c17ea5a7f68e3b041092239142/historico_mensal_vila_v2.py' -OutFile $novo
$hashEsperado = 'a33f182b0409217146dff587e4831ed12b39af116a80aef30802b0d57b0f88d0'
if ((Get-FileHash $novo -Algorithm SHA256).Hash -ne $hashEsperado) {
    throw 'Verificacao do arquivo baixado falhou. Script instalado nao foi alterado.'
}
Move-Item $novo $destino -Force
foreach ($nome in $originaisAntes.Keys) {
    if ((Export-ScheduledTask -TaskName $nome) -ne $originaisAntes[$nome]) {
        throw "Configuracao original mudou durante a correcao: $nome."
    }
}
Write-Host 'V2 INSTALADA. Tarefas de vendas e CMV preservadas.'
$anterior = (Get-ScheduledTaskInfo -TaskName $tarefa).LastRunTime
$limite = (Get-Date).AddMinutes(15)
Start-ScheduledTask -TaskName $tarefa
Write-Host 'TESTE REAL PELO AGENDADOR INICIADO. Aguarde...'
do {
    Start-Sleep -Seconds 5
    $info = Get-ScheduledTaskInfo -TaskName $tarefa
    $estado = (Get-ScheduledTask -TaskName $tarefa).State
    $iniciou = $info.LastRunTime -gt $anterior
} while ((!$iniciou -or $estado -eq 'Running') -and (Get-Date) -lt $limite)
Write-Host ''
Write-Host 'RESULTADO:'
$info | Select-Object LastRunTime, LastTaskResult, NextRunTime | Format-List
Write-Host "ESTADO: $estado"
Get-Content (Join-Path $raiz 'logs\historico.log') -Tail 36
if (!$iniciou -or $estado -eq 'Running') {
    Write-Host 'PENDENTE: teste ainda nao terminou. Nao iniciar outro em paralelo.'
} elseif ($info.LastTaskResult -eq 0) {
    Write-Host 'TESTE DO AGENDADOR CONCLUIDO COM CODIGO 0. Envie o resultado para conferencia final do banco.'
} else {
    Write-Host 'TESTE NAO PASSOU. Envie o resultado para diagnostico.'
}
