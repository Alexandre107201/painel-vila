$ErrorActionPreference = 'Stop'
foreach ($file in @('hands-session.dpapi','writer.dpapi','config.json','hands_publish.py','run-publish.ps1','.venv\Scripts\python.exe')) {
  if (!(Test-Path (Join-Path $PSScriptRoot $file))) { throw "Arquivo ausente: $file" }
}
if (Get-ScheduledTask -TaskName 'Vila-Hands-CMV' -ErrorAction SilentlyContinue) {
  throw 'A tarefa Vila-Hands-CMV já existe. Não foi substituída; envie essa mensagem para conferência.'
}
$account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$cred = Get-Credential -UserName $account -Message 'Senha do usuário Windows atual (não é a senha Hands nem Supabase; PIN não serve)'
if (!$cred -or $cred.UserName -ne $account) { throw 'Use a mesma conta Windows da configuração.' }
$action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'run-publish.ps1') + '"') -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 60) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
try {
  Register-ScheduledTask -TaskName 'Vila-Hands-CMV' -Action $action -Trigger $trigger -Settings $settings -User $account -Password $cred.GetNetworkCredential().Password -RunLevel Limited -Description 'Captura CMV Hands isolada em segundo plano a cada 60 minutos' | Out-Null
} finally { $cred = $null }
Write-Host 'AGENDAMENTO CRIADO | Vila-Hands-CMV | a cada 60 minutos | primeira execução em aproximadamente 1 minuto'
Get-ScheduledTaskInfo -TaskName 'Vila-Hands-CMV' | Select-Object NextRunTime, LastTaskResult
