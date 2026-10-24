# Run in an elevated PowerShell as the SAME dedicated Windows account used for setup.
$ErrorActionPreference = 'Stop'
$account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$cred = Get-Credential -UserName $account -Message 'Senha da conta Windows dedicada (não é a senha Hands)'
if ($cred.UserName -ne $account) { throw 'Use a mesma conta Windows da configuração DPAPI.' }
if (!(Test-Path (Join-Path $PSScriptRoot 'secrets.dpapi'))) { throw 'Execute setup_session.py primeiro.' }
$config = Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
if (!$config.selectors_validated) { throw 'Homologue os seletores antes de agendar.' }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'run.ps1') + '"') -WorkingDirectory $PSScriptRoot
# Explicit duration avoids the default one-day repetition window.
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 60) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'Vila-Hands-CMV' -Action $action -Trigger $trigger -Settings $settings -User $account -Password $cred.GetNetworkCredential().Password -RunLevel Limited -Description 'CMV Hands isolado, headless, a cada 60 minutos' -Force
$cred = $null
