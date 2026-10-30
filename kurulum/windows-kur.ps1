# Gözcü ajanını Windows'a kurar (yönetici olarak çalıştırılmalı).
# Kullanım: powershell -ExecutionPolicy Bypass -File windows-kur.ps1 [-Token <gizli> | -TokenFile <dosya>] [-UserHome C:\Users\<ad>] [-Name <ad>] [-LhmDir <klasör>]
# Token verilmezse yenisi üretilir ve sonunda ekrana yazılır.
param(
  [string] $Token = "",
  [string] $TokenFile = "",
  [string] $UserHome = $env:USERPROFILE,
  [string] $Name = $env:COMPUTERNAME,
  [string] $AjanExe = "$PSScriptRoot\gozcu-ajan.exe",
  [string] $LhmDir = ""
)
$ErrorActionPreference = "Stop"
if (-not $Token -and $TokenFile) { $Token = (Get-Content $TokenFile -Raw).Trim(); Remove-Item $TokenFile -Force }
if (-not $Token) { $b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); $Token = -join ($b | ForEach-Object { $_.ToString("x2") }) }
if ($Token.Length -lt 16) { throw "Token en az 16 karakter olmalı" }
$dir = "C:\ProgramData\Gozcu"
New-Item -ItemType Directory -Force $dir | Out-Null

# 1) Ajan ve ayarları
Get-Process gozcu-ajan -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
Copy-Item $AjanExe "$dir\gozcu-ajan.exe" -Force
$cfg = [ordered]@{
  name = $Name; listen = "0.0.0.0:7420"; token = $Token; user_home = $UserHome
  ollama_url = "http://127.0.0.1:11434"; sustain_secs = 15; grace_secs = 180; auto_stop_ai = $true
  thresholds = [ordered]@{ cpu_warn = 85; cpu_danger = 95; gpu_warn = 80; gpu_danger = 87 }
}
[IO.File]::WriteAllText("$dir\ajan.json", ($cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
# Token yalnız SYSTEM ve yöneticiler tarafından okunabilsin
icacls "$dir\ajan.json" /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null

# 2) LibreHardwareMonitor (işlemci ısısı ve fanlar için), web sunucusu yalnız bu makinede kullanılır
if ($LhmDir -and (Test-Path "$LhmDir\LibreHardwareMonitor.exe")) {
  Get-Process LibreHardwareMonitor -ErrorAction SilentlyContinue | Stop-Process -Force
  Copy-Item "$LhmDir\*" "$dir\lhm" -Recurse -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path "$dir\lhm")) { Copy-Item $LhmDir "$dir\lhm" -Recurse -Force }
  @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <appSettings>
    <add key="startMinMenuItem" value="true" />
    <add key="minTrayMenuItem" value="true" />
    <add key="minCloseMenuItem" value="true" />
    <add key="runWebServerMenuItem" value="true" />
    <add key="listenerPort" value="8085" />
  </appSettings>
</configuration>
'@ | Set-Content -Encoding UTF8 "$dir\lhm\LibreHardwareMonitor.config"
  schtasks /Create /TN "Gozcu\LHM" /TR "`"$dir\lhm\LibreHardwareMonitor.exe`"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F | Out-Null
  schtasks /Run /TN "Gozcu\LHM" | Out-Null
}

# 3) Ajan açılışta SYSTEM olarak başlasın, düşerse yeniden başlasın
$action = New-ScheduledTaskAction -Execute "$dir\gozcu-ajan.exe" -Argument "--config `"$dir\ajan.json`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Ajan" -TaskPath "\Gozcu\" -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskPath "\Gozcu\" -TaskName "Ajan"

# 4) Güvenlik duvarı: yalnız Tailscale ağı
Remove-NetFirewallRule -DisplayName "Gozcu ajan (yalniz Tailscale)" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Gozcu ajan (yalniz Tailscale)" -Direction Inbound -Protocol TCP -LocalPort 7420 `
  -RemoteAddress 100.64.0.0/10 -Action Allow -Profile Any | Out-Null

# LibreHardwareMonitor'ün web sunucusu yalnız bu makinedeki ajan içindir; dışarıdan erişimi kapat
Remove-NetFirewallRule -DisplayName "Gozcu LHM (disariya kapali)" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Gozcu LHM (disariya kapali)" -Direction Inbound -Protocol TCP -LocalPort 8085 `
  -Action Block -Profile Any | Out-Null

Start-Sleep 4
netstat -ano | findstr ":7420" | findstr LISTENING
netstat -ano | findstr ":8085" | findstr LISTENING

$ip = (& tailscale ip -4 2>$null | Select-Object -First 1)
if (-not $ip) { $ip = "<tailscale-ip>" }
Write-Host ""
Write-Host "Kuruldu. Mac'te Gözcü -> Ayarlar -> Makine ekle:"
Write-Host "  Ad:     $Name"
Write-Host "  Adres:  http://${ip}:7420"
Write-Host "  Token:  $Token"
