#requires -RunAsAdministrator
<#
  Optimize-LTSC24H2.ps1
  Perfil: agresivo pero usable
  Objetivo: menos procesos, menos RAM usada en segundo plano, menos telemetría y menos carga inútil
  Probado para Windows 11 LTSC 24H2 / PowerShell 5.1+

  IMPORTANTE:
  - Reinicia al terminar.
  - Lee y ajusta los toggles de abajo antes de ejecutarlo.
#>

# =========================
# TOGGLES
# =========================
$DisableSearchIndexing        = $true   # Desactiva indexado de Windows Search (Start/Search será más simple)
$DisableSysMain               = $true   # Reduce precarga en RAM y actividad en segundo plano
$DisableBluetoothServices     = $false  # Ponlo en $true solo si NO usas Bluetooth
$DisablePrintSpooler          = $false  # Ponlo en $true solo si NO imprimes nunca
$DisableBiometricService      = $false  # Ponlo en $true si no usas lector biométrico / Windows Hello biométrico
$DisableLocationServices      = $true
$DisableErrorReporting        = $true
$DisableFaxService            = $true
$DisableXboxServices          = $true
$DisableRemoteRegistry        = $true
$DisableVisualEffects         = $true
$DisableHibernation           = $false  # Si quieres ahorrar espacio y quitar hiberfile.sys => $true
$SetHighPerformancePlan       = $true   # Modo enchufado = agresivo
$DisableHyperV_WSL_Sandbox    = $false  # SOLO si no usas Docker / WSL / emuladores / Sandbox / virtualización
$RunComponentCleanup          = $true
$KillOneDriveIfRunning        = $true   # Solo mata el proceso; no desinstala
$DisableEdgeBackgroundMode    = $true
$DisableBackgroundApps        = $true
$DisableWidgetsAndSuggestions = $true
$DisableTelemetryPolicies     = $true
$DisableFeedbackTasks         = $true
$ClearTempFiles               = $true

# =========================
# PREP
# =========================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$BaseDir = "C:\LTSC-OPT"
$LogFile = Join-Path $BaseDir ("optimize-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

function Write-Log {
    param([string]$Text)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text
    $line | Tee-Object -FilePath $LogFile -Append
}

Start-Transcript -Path (Join-Path $BaseDir ("transcript-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")) -Force | Out-Null

Write-Log "=== INICIO OPTIMIZACION LTSC 24H2 ==="

# =========================
# HELPERS
# =========================
function Ensure-RegistryPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
}

function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [ValidateSet('String','ExpandString','Binary','DWord','MultiString','QWord')]
        [string]$Type = 'DWord',
        [object]$Value
    )
    try {
        Ensure-RegistryPath $Path
        New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
        Write-Log "REG OK -> $Path :: $Name = $Value"
    } catch {
        Write-Log "REG FAIL -> $Path :: $Name"
    }
}

function Disable-ServiceSafe {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        try {
            if ($svc.Status -ne 'Stopped') {
                Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        try {
            Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        } catch {
            cmd /c "sc.exe config `"$Name`" start= disabled" | Out-Null
        }
        Write-Log "SERVICE DISABLED -> $Name"
    } else {
        Write-Log "SERVICE SKIP (not found) -> $Name"
    }
}

function Manual-ServiceSafe {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        try {
            Set-Service -Name $Name -StartupType Manual -ErrorAction Stop
        } catch {
            cmd /c "sc.exe config `"$Name`" start= demand" | Out-Null
        }
        Write-Log "SERVICE MANUAL -> $Name"
    } else {
        Write-Log "SERVICE SKIP (not found) -> $Name"
    }
}

function Disable-TaskSafe {
    param([string]$TaskPath)
    try {
        schtasks /Change /TN $TaskPath /Disable | Out-Null
        Write-Log "TASK DISABLED -> $TaskPath"
    } catch {
        Write-Log "TASK SKIP/FAIL -> $TaskPath"
    }
}

function Disable-OptionalFeatureSafe {
    param([string]$FeatureName)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName
        if ($f -and $f.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName $FeatureName -NoRestart | Out-Null
            Write-Log "FEATURE DISABLED -> $FeatureName"
        } else {
            Write-Log "FEATURE SKIP -> $FeatureName ($($f.State))"
        }
    } catch {
        Write-Log "FEATURE FAIL/SKIP -> $FeatureName"
    }
}

function Remove-TempSafe {
    param([string]$PathToClean)
    if (Test-Path $PathToClean) {
        try {
            Get-ChildItem -Path $PathToClean -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Write-Log "TEMP CLEANED -> $PathToClean"
        } catch {
            Write-Log "TEMP CLEAN FAIL -> $PathToClean"
        }
    }
}

function Set-PerformancePlan {
    Write-Log "Aplicando plan de energia alto rendimiento..."
    try {
        cmd /c "powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" | Out-Null
        cmd /c "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100" | Out-Null
        cmd /c "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100" | Out-Null
        cmd /c "powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5" | Out-Null
        cmd /c "powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 85" | Out-Null
        cmd /c "powercfg /setactive SCHEME_CURRENT" | Out-Null
        Write-Log "PLAN DE ENERGIA OK"
    } catch {
        Write-Log "PLAN DE ENERGIA FAIL"
    }
}

# =========================
# RESTORE POINT
# =========================
try {
    Enable-ComputerRestore -Drive "$($env:SystemDrive)\" | Out-Null
    Checkpoint-Computer -Description "Antes de optimizar LTSC24H2" -RestorePointType "MODIFY_SETTINGS" | Out-Null
    Write-Log "Restore point creado"
} catch {
    Write-Log "No se pudo crear restore point (continuando)"
}

# =========================
# 1) POLITICAS / TELEMETRIA
# =========================
if ($DisableTelemetryPolicies) {
    Write-Log "Aplicando politicas de privacidad y telemetria..."

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "MaxTelemetryAllowed" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" "DWord" 1
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" "DWord" 2
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\AdvertisingInfo" "DisabledByGroupPolicy" "DWord" 1
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" "DWord" 0
    Set-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" "DWord" 1

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" "DWord" 1
    Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" "DWord" 1
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "DWord" 0
}

if ($DisableWidgetsAndSuggestions) {
    Write-Log "Desactivando sugerencias, widgets y ruido visual..."
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353694Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "DWord" 1
}

if ($DisableBackgroundApps) {
    Write-Log "Desactivando background apps..."
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" "DWord" 1
}

if ($DisableEdgeBackgroundMode) {
    Write-Log "Desactivando background mode de Edge..."
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" "DWord" 0
}

# =========================
# 2) VISUAL / UX
# =========================
if ($DisableVisualEffects) {
    Write-Log "Aplicando modo visual ligero..."
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" "DWord" 2
    Set-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "String" "0"
    Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "String" "0"
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\DWM" "EnableAeroPeek" "DWord" 0
}

# =========================
# 3) GAME DVR / XBOX
# =========================
Write-Log "Desactivando Game DVR..."
Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" "DWord" 0
Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" "DWord" 0
Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" "DWord" 0

# =========================
# 4) SERVICIOS
# =========================
Write-Log "Ajustando servicios..."

Disable-ServiceSafe "DiagTrack"          # Telemetry
Disable-ServiceSafe "MapsBroker"         # Maps broker
Disable-ServiceSafe "RetailDemo"         # Retail demo
Disable-ServiceSafe "PhoneSvc"           # Phone service

if ($DisableLocationServices)  { Disable-ServiceSafe "lfsvc" }
if ($DisableErrorReporting)    { Disable-ServiceSafe "WerSvc" }
if ($DisableFaxService)        { Disable-ServiceSafe "Fax" }
if ($DisableRemoteRegistry)    { Disable-ServiceSafe "RemoteRegistry" }
if ($DisableSysMain)           { Disable-ServiceSafe "SysMain" }
if ($DisableSearchIndexing)    { Disable-ServiceSafe "WSearch" }
if ($DisableXboxServices)      {
    Disable-ServiceSafe "XblAuthManager"
    Disable-ServiceSafe "XblGameSave"
    Disable-ServiceSafe "XboxNetApiSvc"
}
if ($DisableBluetoothServices) {
    Disable-ServiceSafe "bthserv"
    Disable-ServiceSafe "BthAvctpSvc"
}
if ($DisablePrintSpooler)      { Disable-ServiceSafe "Spooler" }
if ($DisableBiometricService)  { Disable-ServiceSafe "WbioSrvc" }

# Servicios que prefiero dejar en manual, no matar completamente
Manual-ServiceSafe "dmwappushservice"

# =========================
# 5) TAREAS PROGRAMADAS
# =========================
if ($DisableFeedbackTasks) {
    Write-Log "Desactivando tareas programadas ruidosas..."

    $Tasks = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\PcaPatchDbTask",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Autochk\Proxy",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
        "\Microsoft\Windows\Maps\MapsToastTask",
        "\Microsoft\Windows\Maps\MapsUpdateTask"
    )

    foreach ($task in $Tasks) {
        Disable-TaskSafe $task
    }
}

# =========================
# 6) CARACTERISTICAS OPCIONALES
# =========================
if ($DisableHyperV_WSL_Sandbox) {
    Write-Log "Desactivando Hyper-V / WSL / Sandbox..."
    $Features = @(
        "Microsoft-Hyper-V-All",
        "VirtualMachinePlatform",
        "HypervisorPlatform",
        "Containers-DisposableClientVM",
        "Microsoft-Windows-Subsystem-Linux",
        "Windows-Defender-ApplicationGuard"
    )

    foreach ($feature in $Features) {
        Disable-OptionalFeatureSafe $feature
    }

    Disable-ServiceSafe "vmcompute"
    Disable-ServiceSafe "HvHost"
    Disable-ServiceSafe "hns"
}

# =========================
# 7) ENERGIA
# =========================
if ($SetHighPerformancePlan) {
    Set-PerformancePlan
}

if ($DisableHibernation) {
    Write-Log "Desactivando hibernacion..."
    cmd /c "powercfg /h off" | Out-Null
}

# =========================
# 8) PROCESOS Y LIMPIEZA
# =========================
if ($KillOneDriveIfRunning) {
    Write-Log "Cerrando OneDrive si esta abierto..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

if ($ClearTempFiles) {
    Write-Log "Limpiando temporales..."
    Remove-TempSafe $env:TEMP
    Remove-TempSafe "$env:WINDIR\Temp"
    Remove-TempSafe "$env:LOCALAPPDATA\Temp"
}

if ($RunComponentCleanup) {
    Write-Log "Ejecutando limpieza de componentes..."
    Start-Process -FilePath "dism.exe" -ArgumentList "/Online","/Cleanup-Image","/StartComponentCleanup" -Wait -NoNewWindow
}

# =========================
# 9) REINICIO DE EXPLORER
# =========================
Write-Log "Reiniciando Explorer..."
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe

Write-Log "=== OPTIMIZACION FINALIZADA ==="
Stop-Transcript | Out-Null

Write-Host ""
Write-Host "Listo. Reinicia la PC para aplicar todo al 100%." -ForegroundColor Green
Write-Host "Log: $LogFile" -ForegroundColor Cyan