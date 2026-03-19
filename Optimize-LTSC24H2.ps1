#requires -RunAsAdministrator
<#
    Optimize-LTSC24H2-SAFE.ps1
    Windows 11 Enterprise LTSC 24H2 - Safe Profile

    Objetivo:
    - Bajar ruido de fondo y mejorar respuesta
    - Evitar cambios agresivos que puedan desestabilizar el sistema
    - Crear respaldos antes de tocar nada
    - NO desactivar por defecto:
        * Windows Search
        * Hyper-V / WSL / Sandbox
        * Bluetooth
        * Print Spooler
        * Biometrics
        * Servicios base de red/audio/GPU/Defender/Windows Update

    Recomendación:
    - Ejecutarlo solo cuando Windows Update no esté instalando nada
    - Reiniciar al terminar
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# =========================
# TOGGLES SEGUROS
# =========================
$CreateRestorePoint            = $true
$ApplyPrivacyTweaks            = $true
$ApplyVisualTweaks             = $true
$ApplyWidgetsSuggestions       = $true
$ApplyBackgroundAppTweaks      = $true
$ApplyEdgeTweaks               = $true
$ApplyGameDVRTweaks            = $true
$ApplyPowerPlanTuning          = $true
$ApplyConservativeTaskTweaks   = $true
$ClearTempFiles                = $true

# Opcionales conservadores (por defecto en false)
$SetXboxServicesToManual       = $true    # Manual, NO Disabled
$SetSysMainToManual            = $false   # Mejor dejarlo false por seguridad
$RestartExplorerAtEnd          = $false   # Mejor reiniciar Windows manualmente
$RunDismCleanup                = $false   # Lo dejo OFF por seguridad

# =========================
# PATHS / LOGS
# =========================
$BaseDir    = "C:\LTSC-SAFE-OPT"
$BackupDir  = Join-Path $BaseDir "backup"
$ReportDir  = Join-Path $BaseDir "reports"
$LogFile    = Join-Path $BaseDir ("run-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$Stamp      = Get-Date -Format "yyyyMMdd-HHmmss"

New-Item -ItemType Directory -Path $BaseDir   -Force | Out-Null
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

function Write-Log {
    param([string]$Text)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text
    $line | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $line
}

function Ensure-RegistryPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
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

function Export-RegSafe {
    param(
        [string]$RegistryPath,
        [string]$OutputFile
    )
    try {
        reg export $RegistryPath $OutputFile /y | Out-Null
        Write-Log "REG BACKUP OK -> $RegistryPath"
    } catch {
        Write-Log "REG BACKUP FAIL -> $RegistryPath"
    }
}

function Set-ServiceToManualSafe {
    param([string]$Name)

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        $svc | Select-Object Name, DisplayName, Status, StartType |
            Export-Csv -Path (Join-Path $BackupDir ("service-$Name-$Stamp.csv")) -NoTypeInformation -Encoding UTF8

        Set-Service -Name $Name -StartupType Manual -ErrorAction Stop
        Write-Log "SERVICE MANUAL -> $Name"

        # No lo forzamos a parar si está corriendo en este momento
    } catch {
        Write-Log "SERVICE SKIP/FAIL -> $Name"
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

function Capture-SystemSnapshot {
    param([string]$Suffix)

    try {
        Get-Process |
            Sort-Object CPU -Descending |
            Select-Object -First 40 Name, Id, CPU, WS, PM, Handles, StartTime |
            Export-Csv -Path (Join-Path $ReportDir ("top-processes-$Suffix.csv")) -NoTypeInformation -Encoding UTF8
        Write-Log "SNAPSHOT OK -> top-processes-$Suffix.csv"
    } catch {
        Write-Log "SNAPSHOT FAIL -> processes"
    }

    try {
        Get-Service |
            Sort-Object Status, DisplayName |
            Select-Object Name, DisplayName, Status, StartType |
            Export-Csv -Path (Join-Path $ReportDir ("services-$Suffix.csv")) -NoTypeInformation -Encoding UTF8
        Write-Log "SNAPSHOT OK -> services-$Suffix.csv"
    } catch {
        Write-Log "SNAPSHOT FAIL -> services"
    }

    try {
        cmd /c "powercfg /getactivescheme" | Out-File -FilePath (Join-Path $ReportDir ("powerplan-$Suffix.txt")) -Encoding utf8
        Write-Log "SNAPSHOT OK -> powerplan-$Suffix.txt"
    } catch {
        Write-Log "SNAPSHOT FAIL -> powerplan"
    }

    try {
        Get-CimInstance Win32_OperatingSystem |
            Select-Object CSName, Caption, Version, BuildNumber, LastBootUpTime, FreePhysicalMemory, TotalVisibleMemorySize |
            Export-Csv -Path (Join-Path $ReportDir ("os-$Suffix.csv")) -NoTypeInformation -Encoding UTF8
        Write-Log "SNAPSHOT OK -> os-$Suffix.csv"
    } catch {
        Write-Log "SNAPSHOT FAIL -> os"
    }
}

function Set-HighPerformancePlanSafe {
    try {
        cmd /c "powercfg /setactive SCHEME_MIN" | Out-Null
        Write-Log "POWER PLAN -> High Performance (SCHEME_MIN)"
    } catch {
        Write-Log "POWER PLAN FAIL"
    }
}

# =========================
# PRECHECK
# =========================
Write-Log "=== SAFE OPTIMIZER START ==="

try {
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("OS -> {0} | Version {1} | Build {2}" -f $os.Caption, $os.Version, $os.BuildNumber)
} catch {}

# Respaldos clave
Export-RegSafe "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" (Join-Path $BackupDir "HKCU-Explorer-Advanced.reg")
Export-RegSafe "HKCU\Software\Microsoft\Windows\DWM" (Join-Path $BackupDir "HKCU-DWM.reg")
Export-RegSafe "HKCU\Software\Microsoft\InputPersonalization" (Join-Path $BackupDir "HKCU-InputPersonalization.reg")
Export-RegSafe "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" (Join-Path $BackupDir "HKCU-AdvertisingInfo.reg")
Export-RegSafe "HKCU\System\GameConfigStore" (Join-Path $BackupDir "HKCU-GameConfigStore.reg")
Export-RegSafe "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" (Join-Path $BackupDir "HKCU-GameDVR.reg")
Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" (Join-Path $BackupDir "HKLM-CloudContent.reg")
Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" (Join-Path $BackupDir "HKLM-AppPrivacy.reg")
Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" (Join-Path $BackupDir "HKLM-System.reg")
Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Edge" (Join-Path $BackupDir "HKLM-Edge.reg")
Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" (Join-Path $BackupDir "HKLM-GameDVR.reg")

Capture-SystemSnapshot -Suffix "before"

# Punto de restauración
if ($CreateRestorePoint) {
    try {
        Enable-ComputerRestore -Drive "$($env:SystemDrive)\" | Out-Null
        Checkpoint-Computer -Description "Before LTSC Safe Optimizer" -RestorePointType "MODIFY_SETTINGS" | Out-Null
        Write-Log "RESTORE POINT -> created"
    } catch {
        Write-Log "RESTORE POINT -> skipped/fail"
    }
}

# =========================
# PRIVACY / USER EXPERIENCE
# =========================
if ($ApplyPrivacyTweaks) {
    Write-Log "Applying privacy tweaks..."

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" "DWord" 1
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" "DWord" 0

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" "DWord" 1
    Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" "DWord" 1
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "DWord" 0
}

if ($ApplyWidgetsSuggestions) {
    Write-Log "Applying widgets and suggestions tweaks..."

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" "DWord" 0

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353694Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" "DWord" 0
}

if ($ApplyBackgroundAppTweaks) {
    Write-Log "Applying background apps tweaks..."

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" "DWord" 2
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" "DWord" 1
}

if ($ApplyEdgeTweaks) {
    Write-Log "Applying Edge background tweaks..."

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" "DWord" 0
}

if ($ApplyGameDVRTweaks) {
    Write-Log "Applying Game DVR tweaks..."

    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" "DWord" 0
}

if ($ApplyVisualTweaks) {
    Write-Log "Applying visual tweaks..."

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" "DWord" 2
    Set-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "String" "0"
    Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "String" "0"
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\DWM" "EnableAeroPeek" "DWord" 0
}

# =========================
# SERVICES (CONSERVATIVE)
# =========================
if ($SetXboxServicesToManual) {
    Write-Log "Setting Xbox services to Manual..."
    Set-ServiceToManualSafe "XblAuthManager"
    Set-ServiceToManualSafe "XblGameSave"
    Set-ServiceToManualSafe "XboxNetApiSvc"
}

if ($SetSysMainToManual) {
    Write-Log "Setting SysMain to Manual..."
    Set-ServiceToManualSafe "SysMain"
}

# =========================
# TASKS (CONSERVATIVE)
# =========================
if ($ApplyConservativeTaskTweaks) {
    Write-Log "Applying conservative scheduled-task tweaks..."

    $Tasks = @(
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\Feedback\Siuf\DmClient",
        "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
    )

    foreach ($task in $Tasks) {
        Disable-TaskSafe $task
    }
}

# =========================
# POWER
# =========================
if ($ApplyPowerPlanTuning) {
    Write-Log "Applying power plan..."
    Set-HighPerformancePlanSafe
}

# =========================
# CLEANUP
# =========================
if ($ClearTempFiles) {
    Write-Log "Cleaning temp files..."
    Remove-TempSafe $env:TEMP
    Remove-TempSafe "$env:LOCALAPPDATA\Temp"
    Remove-TempSafe "$env:WINDIR\Temp"
}

if ($RunDismCleanup) {
    Write-Log "Running DISM cleanup..."
    Start-Process -FilePath "dism.exe" -ArgumentList "/Online","/Cleanup-Image","/StartComponentCleanup" -Wait -NoNewWindow
}

# =========================
# FINAL SNAPSHOT
# =========================
Capture-SystemSnapshot -Suffix "after"

if ($RestartExplorerAtEnd) {
    try {
        Write-Log "Restarting Explorer..."
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    } catch {
        Write-Log "Explorer restart skipped/fail"
    }
}

Write-Log "=== SAFE OPTIMIZER END ==="
Write-Host ""
Write-Host "Listo. Reinicia Windows para aplicar los cambios de forma limpia." -ForegroundColor Green
Write-Host "Logs y respaldos en: $BaseDir" -ForegroundColor Cyan
Write-Host "Si algo raro pasa, revisa primero: $ReportDir" -ForegroundColor Yellow