#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Status', 'Apply', 'Restore')]
    [string]$Action = 'Status',

    [string]$Dota2Path,
    [string]$Cs2Path
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    throw 'Run this script in PowerShell on Windows 11.'
}

$backupPath = Join-Path $env:LOCALAPPDATA 'Windows11GamingTweaks\backup.json'

function Get-SteamLibrary {
    $steamPath = [Microsoft.Win32.Registry]::GetValue(
        'HKEY_CURRENT_USER\Software\Valve\Steam', 'SteamPath', $null
    )
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $roots = @(
        if ($steamPath) { $steamPath }
        if ($programFilesX86) { Join-Path $programFilesX86 'Steam' }
        if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Steam' }
    )

    $libraries = foreach ($root in $roots | Select-Object -Unique) {
        if (-not [System.IO.Directory]::Exists($root)) { continue }
        $apps = Join-Path $root 'steamapps'
        $foldersFile = Join-Path $apps 'libraryfolders.vdf'
        if (Test-Path -LiteralPath $apps -PathType Container) { $apps }
        if (-not (Test-Path -LiteralPath $foldersFile -PathType Leaf)) { continue }

        [string]$content = Get-Content -LiteralPath $foldersFile -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($content, '(?im)^\s*"path"\s+"([^"\r\n]+)"')) {
            $library = $match.Groups[1].Value.Replace('\\', '\')
            if ([System.IO.Directory]::Exists($library)) { Join-Path $library 'steamapps' }
        }
    }

    $libraries | Select-Object -Unique
}

function Find-GameExecutable($Override, $ExeName, $AppId, $DefaultFolder, $Libraries) {
    if ($Override) {
        $item = Get-Item -LiteralPath $Override
        if ($item -isnot [System.IO.FileInfo] -or $item.Name -ne $ExeName) {
            throw "Expected a path to $ExeName. Received '$Override'."
        }
        return $item.FullName
    }

    foreach ($library in $Libraries) {
        $folder = $DefaultFolder
        $manifest = Join-Path $library "appmanifest_$AppId.acf"
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            $content = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
            if ($content -match '(?im)^\s*"installdir"\s+"([^"\\/:]+)"' -and $Matches[1] -notin '.', '..') {
                $folder = $Matches[1]
            }
        }

        $exe = Join-Path $library "common\$folder\game\bin\win64\$ExeName"
        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            return (Get-Item -LiteralPath $exe).FullName
        }
    }
}

function Get-RegistryTarget([string]$Name) {
    if ($Name -eq 'AutoGameModeEnabled') {
        return @{ Key = 'Software\Microsoft\GameBar'; Kind = [Microsoft.Win32.RegistryValueKind]::DWord }
    }

    if ($Name -match '^(?:[A-Z]:\\(?:[^\r\n]*\\)?|\\\\[^\r\n]+\\)(?:dota2|cs2)\.exe$') {
        return @{ Key = 'Software\Microsoft\DirectX\UserGpuPreferences'; Kind = [Microsoft.Win32.RegistryValueKind]::String }
    }

    throw "Unexpected setting name '$Name'."
}

function Read-GamingValue([string]$Name) {
    $target = Get-RegistryTarget $Name
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($target.Key)
    if ($null -eq $key) { return }

    try {
        if ($key.GetValueNames() -notcontains $Name) { return }
        if ($key.GetValueKind($Name) -ne $target.Kind) {
            throw "Unexpected registry type for '$Name'."
        }
        $key.GetValue($Name)
    }
    finally {
        $key.Dispose()
    }
}

function Write-GamingValue([string]$Name, $Value) {
    $target = Get-RegistryTarget $Name
    if ($null -eq $Value) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($target.Key, $true)
        if ($null -eq $key) { return }
    }
    else {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($target.Key)
    }

    try {
        if ($null -eq $Value) {
            $key.DeleteValue($Name, $false)
        }
        elseif ($target.Kind -eq 'DWord') {
            $key.SetValue($Name, [int]$Value, $target.Kind)
        }
        else {
            $key.SetValue($Name, [string]$Value, $target.Kind)
        }
    }
    finally {
        $key.Dispose()
    }
}

function Get-HighPerformancePreference([string]$Value) {
    $pattern = '(?i)(^|;)GpuPreference=[^;]*'
    if ($Value -match $pattern) {
        return [regex]::Replace($Value, $pattern, '${1}GpuPreference=2')
    }

    if ($Value -and -not $Value.EndsWith(';')) { $Value += ';' }
    return "${Value}GpuPreference=2;"
}

function Get-GamingSettings {
    $gameMode = 'AutoGameModeEnabled'
    [pscustomobject]@{ Label = 'Windows Game Mode'; Name = $gameMode; Before = Read-GamingValue $gameMode; After = 1 }

    $libraries = @(Get-SteamLibrary)
    $games = @(
        @{ Label = 'Dota 2'; Override = $Dota2Path; Exe = 'dota2.exe'; Id = '570'; Folder = 'dota 2 beta' }
        @{ Label = 'Counter-Strike 2'; Override = $Cs2Path; Exe = 'cs2.exe'; Id = '730'; Folder = 'Counter-Strike Global Offensive' }
    )

    foreach ($game in $games) {
        $exe = Find-GameExecutable $game.Override $game.Exe $game.Id $game.Folder $libraries
        if (-not $exe) {
            Write-Warning "$($game.Label) executable not found. See the README for path overrides."
            continue
        }

        $current = Read-GamingValue $exe
        $desired = if ($current -match '(?i)(^|;)SpecificAdapter=') {
            Write-Warning "$($game.Label) already has a specific GPU selected. Keeping that selection."
            $current
        }
        else {
            Get-HighPerformancePreference $current
        }

        [pscustomobject]@{ Label = $game.Label; Name = $exe; Before = $current; After = $desired }
    }
}

function Save-Backup($Changes) {
    $directory = Split-Path -Parent $backupPath
    [void][System.IO.Directory]::CreateDirectory($directory)
    $temporary = Join-Path $directory ([System.IO.Path]::GetRandomFileName())
    try {
        $document = @{ Version = 1; Changes = @($Changes) } | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($temporary, $document)
        [System.IO.File]::Move($temporary, $backupPath)
    }
    finally {
        [System.IO.File]::Delete($temporary)
    }
}

function Read-Backup {
    $backup = Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($backup.Version -ne 1 -or $backup.Changes.Count -lt 1 -or $backup.Changes.Count -gt 3) {
        throw "Invalid backup at '$backupPath'."
    }

    foreach ($change in $backup.Changes) {
        $target = Get-RegistryTarget $change.Name
        if ($target.Kind -eq 'DWord') {
            $before = $change.Before
            if ($change.After -ne 1 -or ($null -ne $before -and $before -isnot [int] -and $before -isnot [long])) {
                throw "Invalid Game Mode value in '$backupPath'."
            }
            if ($null -ne $change.Before) { $change.Before = [int]$change.Before }
        }
        elseif ($change.After -isnot [string] -or ($null -ne $change.Before -and $change.Before -isnot [string])) {
            throw "Invalid graphics preference in '$backupPath'."
        }
    }

    $backup.Changes
}

function Format-SettingValue($Value) {
    if ($null -eq $Value) { return '(unset)' }
    if ($Value -is [string] -and $Value.Length -eq 0) { return '(empty)' }
    return [string]$Value
}

if ($Action -eq 'Status') {
    $settings = @(Get-GamingSettings)
    foreach ($setting in $settings) {
        Write-Host "$($setting.Label) [$($setting.Name)] = $(Format-SettingValue $setting.Before)"
    }
    if ([System.IO.File]::Exists($backupPath)) {
        Write-Host "Restore is available from $backupPath"
    }
    return
}

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex = [System.Threading.Mutex]::new($false, "Global\Windows11GamingTweaks.$sid")
$locked = $false
try {
    try {
        $locked = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $locked = $true
    }
    if (-not $locked) { throw 'Another Apply or Restore is already running.' }

    $hasBackup = [System.IO.File]::Exists($backupPath)
    if ($Action -eq 'Apply') {
        if ($hasBackup) {
            Write-Host 'A backup already exists. Run Restore before applying again.'
            return
        }

        $changes = @(Get-GamingSettings | Where-Object { $_.Before -cne $_.After })
        if ($changes.Count -eq 0) {
            Write-Host 'The detected settings are already configured.'
            return
        }
        foreach ($change in $changes) {
            Write-Host "$($change.Label) [$($change.Name)]  $(Format-SettingValue $change.Before) -> $(Format-SettingValue $change.After)"
        }
        if (-not $PSCmdlet.ShouldProcess('current Windows user', 'Apply gaming preferences and save their original values')) { return }

        Save-Backup $changes
        try {
            foreach ($change in $changes) {
                if ((Read-GamingValue $change.Name) -cne $change.Before) {
                    throw "Setting changed during Apply: '$($change.Name)'."
                }
                Write-GamingValue $change.Name $change.After
            }
        }
        catch {
            throw "Apply was interrupted. Run Restore to undo any completed edits. $($_.Exception.Message)"
        }
        Write-Host 'Applied. Restart any open game to pick up the new settings.'
        return
    }

    if (-not $hasBackup) {
        Write-Host 'There is no saved backup to restore.'
        return
    }

    $changes = @(Read-Backup)
    if (-not $PSCmdlet.ShouldProcess('current Windows user', 'Restore saved gaming preferences')) { return }

    $conflict = $false
    foreach ($change in $changes) {
        $current = Read-GamingValue $change.Name
        if ($current -ceq $change.Before) { continue }
        if ($current -cne $change.After) {
            Write-Warning "Keeping a setting changed outside this script: '$($change.Name)'. Saved value: $(Format-SettingValue $change.Before)"
            $conflict = $true
            continue
        }
        Write-GamingValue $change.Name $change.Before
    }
    if ($conflict) {
        throw "Restored available settings. Backup retained at '$backupPath' for the skipped values."
    }
    [System.IO.File]::Delete($backupPath)
    Write-Host 'Restored the saved gaming preferences. Restart any open game.'
}
finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
