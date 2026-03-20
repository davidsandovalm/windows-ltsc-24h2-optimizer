#requires -RunAsAdministrator
<#
    Optimize-LTSC24H2-PERF.ps1
    Windows 11 Enterprise LTSC 24H2

    Perfil:
    - CONSERVATIVE
    - BALANCED
    - AGGRESSIVE

    Enfoque:
    - Optimizar de verdad sin tocar piezas críticas por defecto
    - Respaldos + restore point + snapshots
    - Cambios soportados por políticas/registro/tareas/servicios
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# =========================================================
# PERFIL
# =========================================================
$Profile = "AGGRESSIVE"   # CONSERVATIVE | BALANCED | AGGRESSIVE

# =========================================================
# TOGGLES BASE
# =========================================================
$CreateRestorePoint              = $true
$BackupRegistry                  = $true
$CaptureSnapshots                = $true
$ApplyPrivacyPolicies            = $true
$ApplyUXCleanup                  = $true
$ApplyVisualPerformance          = $true
$ApplyBackgroundAppsRestriction  = $true
$ApplyEdgeTweaks                 = $true
$ApplyGameDVRTweaks              = $true
$ApplyPowerPlan                  = $true
$ClearTempFiles                  = $true
$RunStartComponentCleanupTask    = $false   # opcional, por seguridad lo dejo apagado

# Opciones más delicadas
$DisableWindowsSearch            = $false
$DisableSysMain                  = $false
$DisableLocationService          = $false
$DisableHibernation              = $false
$DisableXboxServices             = $true

# =========================================================
# RUTAS / LOGS
# =========================================================
$BaseDir    = "C:\LTSC-PERF-OPT"
$BackupDir  = Join-Path $BaseDir "backup"
$ReportDir  = Join-Path $BaseDir "reports"
$LogFile    = Join-Path $BaseDir ("run-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$Stamp      = Get-Date -Format "yyyyMMdd-HHmmss"

New-Item -ItemType Directory -Path $BaseDir   -Force | Out-Null
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

# =========================================================
# HELPERS
# =========================================================
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

function Capture-SystemSnapshot {
    param([string]$Suffix)

    try {
        Get-Process |
            Sort-Object CPU -Descending |
            Select-Object -First 60 Name, Id, CPU, WS, PM, Handles, StartTime |
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

function Set-ServiceStartupSafe {
    param(
        [string]$Name,
        [ValidateSet('Automatic','Manual','Disabled')]
        [string]$StartupType
    )

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        $svc | Select-Object Name, DisplayName, Status, StartType |
            Export-Csv -Path (Join-Path $BackupDir ("service-$Name-$Stamp.csv")) -NoTypeInformation -Encoding UTF8

        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        Write-Log "SERVICE OK -> $Name = $StartupType"

        if ($StartupType -eq 'Disabled' -and $svc.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            Write-Log "SERVICE STOP -> $Name"
        }
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

function Set-PerformancePlanSafe {
    try {
        cmd /c "powercfg /setactive SCHEME_MIN" | Out-Null

        # En corriente, full performance
        cmd /c "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100" | Out-Null
        cmd /c "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100" | Out-Null

        # En batería, conservador razonable
        cmd /c "powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5" | Out-Null
        cmd /c "powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 85" | Out-Null

        cmd /c "powercfg /setactive SCHEME_CURRENT" | Out-Null
        Write-Log "POWER PLAN -> High Performance tuned"
    } catch {
        Write-Log "POWER PLAN FAIL"
    }
}

# =========================================================
# AJUSTE DE PERFIL
# =========================================================
switch ($Profile.ToUpper()) {
    "CONSERVATIVE" {
        $DisableWindowsSearch         = $false
        $DisableSysMain               = $false
        $DisableLocationService       = $false
        $DisableHibernation           = $false
        $DisableXboxServices          = $true
    }
    "BALANCED" {
        $DisableWindowsSearch         = $false
        $DisableSysMain               = $false
        $DisableLocationService       = $false
        $DisableHibernation           = $false
        $DisableXboxServices          = $true
    }
    "AGGRESSIVE" {
        $DisableWindowsSearch         = $false
        $DisableSysMain               = $true
        $DisableLocationService       = $false
        $DisableHibernation           = $false
        $DisableXboxServices          = $true
    }
    default {
        Write-Log "Perfil inválido. Usando AGGRESSIVE."
        $Profile = "AGGRESSIVE"
        $DisableWindowsSearch         = $false
        $DisableSysMain               = $true
        $DisableLocationService       = $false
        $DisableHibernation           = $false
        $DisableXboxServices          = $true
    }
}

# =========================================================
# INICIO
# =========================================================
Write-Log "=== LTSC PERF OPTIMIZER START ==="
Write-Log "PROFILE -> $Profile"

try {
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("OS -> {0} | Version {1} | Build {2}" -f $os.Caption, $os.Version, $os.BuildNumber)
} catch {}

if ($BackupRegistry) {
    Export-RegSafe "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" (Join-Path $BackupDir "HKCU-Explorer-Advanced.reg")
    Export-RegSafe "HKCU\Software\Microsoft\Windows\DWM" (Join-Path $BackupDir "HKCU-DWM.reg")
    Export-RegSafe "HKCU\Software\Microsoft\InputPersonalization" (Join-Path $BackupDir "HKCU-InputPersonalization.reg")
    Export-RegSafe "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" (Join-Path $BackupDir "HKCU-AdvertisingInfo.reg")
    Export-RegSafe "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" (Join-Path $BackupDir "HKCU-BackgroundAccessApplications.reg")
    Export-RegSafe "HKCU\System\GameConfigStore" (Join-Path $BackupDir "HKCU-GameConfigStore.reg")
    Export-RegSafe "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" (Join-Path $BackupDir "HKCU-GameDVR.reg")

    Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" (Join-Path $BackupDir "HKLM-CloudContent.reg")
    Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" (Join-Path $BackupDir "HKLM-AppPrivacy.reg")
    Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" (Join-Path $BackupDir "HKLM-System.reg")
    Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Edge" (Join-Path $BackupDir "HKLM-Edge.reg")
    Export-RegSafe "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" (Join-Path $BackupDir "HKLM-GameDVR.reg")
}

if ($CaptureSnapshots) {
    Capture-SystemSnapshot -Suffix "before"
}

if ($CreateRestorePoint) {
    try {
        Enable-ComputerRestore -Drive "$($env:SystemDrive)\" | Out-Null
        Checkpoint-Computer -Description "Before LTSC PERF Optimizer" -RestorePointType "MODIFY_SETTINGS" | Out-Null
        Write-Log "RESTORE POINT -> created"
    } catch {
        Write-Log "RESTORE POINT -> skipped/fail"
    }
}

# =========================================================
# PRIVACY / CLOUD / BACKGROUND
# =========================================================
if ($ApplyPrivacyPolicies) {
    Write-Log "Applying privacy / cloud / activity policies..."

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableCloudOptimizedContent" "DWord" 1
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableConsumerAccountStateContent" "DWord" 1

    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" "DWord" 0

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" "DWord" 1
    Set-RegValue "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" "DWord" 1
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "DWord" 0
}

if ($ApplyBackgroundAppsRestriction) {
    Write-Log "Applying background apps restriction..."
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" "DWord" 2
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" "DWord" 1
}

# =========================================================
# UX / SUGGESTIONS / WIDGETS
# =========================================================
if ($ApplyUXCleanup) {
    Write-Log "Applying UX cleanup..."

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" "DWord" 0

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353694Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" "DWord" 0
}

# =========================================================
# EDGE
# =========================================================
if ($ApplyEdgeTweaks) {
    Write-Log "Applying Edge tweaks..."
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" "DWord" 0
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" "DWord" 0
}

# =========================================================
# GAME DVR / XBOX
# =========================================================
if ($ApplyGameDVRTweaks) {
    Write-Log "Applying Game DVR tweaks..."
    Set-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" "DWord" 0
    Set-RegValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" "DWord" 0
}

# =========================================================
# VISUAL PERFORMANCE
# =========================================================
if ($ApplyVisualPerformance) {
    Write-Log "Applying visual performance tweaks..."

    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" "DWord" 2
    Set-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "String" "0"
    Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "String" "0"
    Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" "DWord" 0
    Set-RegValue "HKCU:\Software\Microsoft\Windows\DWM" "EnableAeroPeek" "DWord" 0
}

# =========================================================
# SERVICES
# =========================================================
Write-Log "Applying service tuning..."

# Siempre seguros para tocar
Set-ServiceStartupSafe "Fax" "Disabled"
Set-ServiceStartupSafe "RemoteRegistry" "Disabled"
Set-ServiceStartupSafe "RetailDemo" "Disabled"
Set-ServiceStartupSafe "MapsBroker" "Disabled"
Set-ServiceStartupSafe "PhoneSvc" "Manual"
Set-ServiceStartupSafe "dmwappushservice" "Manual"

if ($DisableXboxServices) {
    Set-ServiceStartupSafe "XblAuthManager" "Disabled"
    Set-ServiceStartupSafe "XblGameSave" "Disabled"
    Set-ServiceStartupSafe "XboxNetApiSvc" "Disabled"
}

if ($DisableSysMain) {
    Set-ServiceStartupSafe "SysMain" "Disabled"
}

if ($DisableWindowsSearch) {
    Set-ServiceStartupSafe "WSearch" "Disabled"
}

if ($DisableLocationService) {
    Set-ServiceStartupSafe "lfsvc" "Disabled"
}

# =========================================================
# TASKS
# =========================================================
Write-Log "Applying scheduled-task tuning..."

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

# =========================================================
# POWER
# =========================================================
if ($ApplyPowerPlan) {
    Write-Log "Applying power plan tuning..."
    Set-PerformancePlanSafe
}

if ($DisableHibernation) {
    try {
        cmd /c "powercfg /h off" | Out-Null
        Write-Log "HIBERNATION -> disabled"
    } catch {
        Write-Log "HIBERNATION FAIL"
    }
}

# =========================================================
# CLEANUP
# =========================================================
if ($ClearTempFiles) {
    Write-Log "Cleaning temp files..."
    Remove-TempSafe $env:TEMP
    Remove-TempSafe "$env:LOCALAPPDATA\Temp"
    Remove-TempSafe "$env:WINDIR\Temp"
}

if ($RunStartComponentCleanupTask) {
    try {
        schtasks.exe /Run /TN "\Microsoft\Windows\Servicing\StartComponentCleanup" | Out-Null
        Write-Log "STARTCOMPONENTCLEANUP TASK -> started"
    } catch {
        Write-Log "STARTCOMPONENTCLEANUP TASK -> fail"
    }
}

# =========================================================
# FINAL SNAPSHOT
# =========================================================
if ($CaptureSnapshots) {
    Capture-SystemSnapshot -Suffix "after"
}

Write-Log "=== LTSC PERF OPTIMIZER END ==="
Write-Host ""
Write-Host "Listo. Reinicia Windows para aplicar todo de forma limpia." -ForegroundColor Green
Write-Host "Logs / backups / reports: $BaseDir" -ForegroundColor Cyan
Write-Host "Perfil usado: $Profile" -ForegroundColor Yellow