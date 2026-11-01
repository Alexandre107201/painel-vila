$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'CAMERA-PC' -or $env:USERNAME -ne 'CAMERA') {
    throw 'Execute no CAMERA-PC como CAMERA.'
}
$rootHands = 'C:\Users\CAMERA\VilaHands'
$pythonHands = Join-Path $rootHands '.venv\Scripts\python.exe'
$novaTarefa = 'Vila-Hands-CMV-Fechamento-15dias'
$taskOriginal = Get-ScheduledTask -TaskName 'Vila-Hands-CMV' -ErrorAction Stop
if (Get-ScheduledTask -TaskName $novaTarefa -ErrorAction SilentlyContinue) {
    throw 'A tarefa de revisao ja existe; nao sera duplicada. Envie o resultado.'
}
if ($taskOriginal.State -eq 'Running') { throw 'CMV em execucao. Aguarde terminar e repita este comando.' }
$xmlOriginal = Export-ScheduledTask -TaskName 'Vila-Hands-CMV'
$xmlVendas = Export-ScheduledTask -TaskName 'Painel Vila - Atualizar BI'
$backupHands = 'C:\BackupPainelVila\CMV_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $backupHands | Out-Null
Get-ChildItem $rootHands -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $backupHands
}
[IO.File]::WriteAllText((Join-Path $backupHands 'CMV_original.xml'),$xmlOriginal)
Write-Host "BACKUP CONCLUIDO: $backupHands"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$candidato = Join-Path $rootHands 'hands_publish_candidate.py'
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/Alexandre107201/painel-vila/ef395dc836db4da3ef68cffb5509e2d468b67d2c/hands_publish_revisao_15dias.py' -OutFile $candidato
if ((Get-FileHash $candidato -Algorithm SHA256).Hash -ne 'fd5c62c22e9a8cdb91649b78d6ea79aa4b684a34d412ed94d93720c23cb9a424') {
    throw 'Verificacao do arquivo falhou; arquivos ativos nao foram alterados.'
}
try {
    $lockHands = [IO.File]::Open((Join-Path $rootHands 'capture.lock'),'OpenOrCreate','ReadWrite','None')
} catch [IO.IOException] {
    throw 'Outra captura CMV esta em andamento; aguarde e repita.'
}
try {
    Write-Host 'TESTE SOMENTE LEITURA DO MES ATUAL...'
    $ErrorActionPreference = 'Continue'
    & $pythonHands -B $candidato --dry-run
    $testeAtual = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($testeAtual -ne 0) { throw 'Teste do mes atual falhou. Nenhum arquivo ativo foi alterado. Envie a mensagem acima.' }
    Write-Host 'TESTE SOMENTE LEITURA DO FECHAMENTO...'
    $ErrorActionPreference = 'Continue'
    & $pythonHands -B $candidato --closed --dry-run
    $testeFechado = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($testeFechado -ne 0) { throw 'Teste do fechamento falhou. Nenhum arquivo ativo foi alterado. Envie a mensagem acima.' }
    Copy-Item $candidato (Join-Path $rootHands 'hands_publish.py') -Force
    $novoRunner = @'
param([switch]$Closed)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
try {
  $lock = [System.IO.File]::Open((Join-Path $PSScriptRoot 'capture.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch [System.IO.IOException] {
  if ($Closed) { exit 75 } else { exit 0 }
}
$result = 1
try {
  $log = Join-Path $PSScriptRoot $(if ($Closed) {'closed-review.log'} else {'capture.log'})
  if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) { Move-Item $log "$log.1" -Force }
  Add-Content -LiteralPath $log -Value (Get-Date -Format o) -Encoding UTF8
  $python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
  $script = Join-Path $PSScriptRoot 'hands_publish.py'
  if (!(Test-Path $python) -or !(Test-Path $script)) { throw 'Arquivos do robo CMV nao encontrados.' }
  # Captura stderr sem encerrar o PowerShell antes de registrar o erro seguro do Python.
  $ErrorActionPreference = 'Continue'
  if ($Closed) { $output = & $python -u $script --closed 2>&1 }
  else { $output = & $python -u $script 2>&1 }
  $result = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  $output | ForEach-Object { $_.ToString() } | Add-Content -LiteralPath $log -Encoding UTF8
} finally { $lock.Dispose() }
exit $result
'@
    [IO.File]::WriteAllText((Join-Path $rootHands 'run-publish.ps1'),$novoRunner,(New-Object System.Text.UTF8Encoding($false)))
} finally { $lockHands.Dispose() }
if ((Export-ScheduledTask -TaskName 'Vila-Hands-CMV') -ne $xmlOriginal -or
    (Export-ScheduledTask -TaskName 'Painel Vila - Atualizar BI') -ne $xmlVendas) {
    throw 'Uma tarefa original mudou durante a instalacao; conferir antes de agendar.'
}
$sidHands = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$inicioHands = (Get-Date).Date.AddDays(1).AddHours(6).AddMinutes(45).ToString('yyyy-MM-ddTHH:mm:ss')
$xmlHands = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<RegistrationInfo><Description>Revisa o CMV do mes anterior diariamente ate dia 15. Depois preserva o fechamento. Requer CAMERA conectado.</Description></RegistrationInfo>
<Triggers><CalendarTrigger><StartBoundary>$inicioHands</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers>
<Principals><Principal id="Autor"><UserId>$sidHands</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable><Enabled>true</Enabled><Hidden>true</Hidden><ExecutionTimeLimit>PT30M</ExecutionTimeLimit><RestartOnFailure><Interval>PT30M</Interval><Count>3</Count></RestartOnFailure></Settings>
<Actions Context="Autor"><Exec><Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command><Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\CAMERA\VilaHands\run-publish.ps1" -Closed</Arguments><WorkingDirectory>$rootHands</WorkingDirectory></Exec></Actions>
</Task>
"@
Register-ScheduledTask -TaskName $novaTarefa -Xml $xmlHands -ErrorAction Stop | Out-Null
$anteriorHands = (Get-ScheduledTaskInfo -TaskName $novaTarefa).LastRunTime
Start-ScheduledTask -TaskName $novaTarefa
Write-Host 'TESTE REAL DO FECHAMENTO PELO AGENDADOR INICIADO. Aguarde...'
$limiteHands = (Get-Date).AddMinutes(8)
do {
    Start-Sleep -Seconds 5
    $infoHands = Get-ScheduledTaskInfo -TaskName $novaTarefa
    $estadoHands = (Get-ScheduledTask -TaskName $novaTarefa).State
    $iniciouHands = $infoHands.LastRunTime -gt $anteriorHands
} while ((!$iniciouHands -or $estadoHands -eq 'Running') -and (Get-Date) -lt $limiteHands)
$infoHands | Select-Object LastRunTime,LastTaskResult,NextRunTime | Format-List
if (Test-Path (Join-Path $rootHands 'closed-review.log')) {
    Get-Content (Join-Path $rootHands 'closed-review.log') -Tail 12
}
if (!$iniciouHands -or $estadoHands -eq 'Running') {
    Write-Host 'PENDENTE: aguarde o teste terminar; nao inicie outra copia.'
} elseif ($infoHands.LastTaskResult -ne 0) {
    Write-Host 'TESTE NAO PASSOU. Envie este resultado para diagnostico.'
} else {
    Write-Host 'CONCLUIDO: fechamento revisado pelo Agendador. Rotina diaria 06h45, com captura somente do dia 1 ao dia 15.'
    Write-Host 'Tarefas originais de vendas e CMV mantidas. Envie este resultado para conferencia final no banco.'
}
