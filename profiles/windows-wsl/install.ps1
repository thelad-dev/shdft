<#
.SYNOPSIS
Richtet die Windows-Seite von shdft ein: WezTerm-Konfiguration und .wslconfig.

.DESCRIPTION
Kopiert windows\wezterm.lua nach %USERPROFILE%\.config\wezterm\wezterm.lua und windows\.wslconfig
nach %USERPROFILE%\.wslconfig. Abweichende vorhandene Dateien werden vorher nach
%USERPROFILE%\.shdft-backup\<Zeitstempel>\ gesichert. Braucht keine Administratorrechte.
Mehrfach ausführbar: ein zweiter Lauf meldet jede Datei als unverändert.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WhatIf
Zeigt nur, was geschehen würde.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interaktives Installationsskript: die Statuszeilen sind für die Konsole bestimmt.')]
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
# Aus WSL aufgerufen ist die Ausgabe umgeleitet; ohne UTF-8 kämen die Umlaute dort verstümmelt an.
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = [Text.Encoding]::UTF8 }
$repo = $PSScriptRoot
$backupRoot = Join-Path $env:USERPROFILE ('.shdft-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$changedWslConfig = $false

# Statuszeilen gehen über Write-Host, damit Install-RepoFile nur seinen Rückgabewert liefert.
function Write-Status([string]$State, [string]$Path) {
    Write-Host ('  {0,-12} {1}' -f $State, $Path)
}

# Get-FileHash ist in Windows PowerShell 5.1 eine Skriptfunktion, die unter -WhatIf nichts liefert;
# der Vergleich muss im Trockenlauf aber laufen, deshalb direkt über .NET.
function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose() }
}

function Install-RepoFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param([string]$Source, [string]$Target)
    $rel = $Target.Substring($env:USERPROFILE.Length).TrimStart('\')
    $exists = Test-Path -LiteralPath $Target
    if ($exists -and (Get-Sha256 $Source) -eq (Get-Sha256 $Target)) {
        Write-Status 'unverändert' $rel
        return $false
    }
    $what = if ($exists) { 'sichern und durch die Repo-Fassung ersetzen' } else { 'aus dem Repo anlegen' }
    if (-not $PSCmdlet.ShouldProcess($Target, $what)) {
        return $false
    }
    if ($exists) {
        $saved = Join-Path $backupRoot $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $saved) | Out-Null
        Copy-Item -LiteralPath $Target -Destination $saved
        Write-Status 'gesichert' "$rel -> $($saved.Substring($env:USERPROFILE.Length).TrimStart('\'))"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Target) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Target -Force
    Write-Status 'geschrieben' $rel
    return $true
}

Write-Host 'WezTerm und WSL-Einstellungen:'
Install-RepoFile (Join-Path $repo 'windows\wezterm.lua') (Join-Path $env:USERPROFILE '.config\wezterm\wezterm.lua') | Out-Null
$changedWslConfig = Install-RepoFile (Join-Path $repo 'windows\.wslconfig') (Join-Path $env:USERPROFILE '.wslconfig')

Write-Host ''
Write-Host 'Fertig. WezTerm lädt wezterm.lua beim Speichern selbst neu.'
if ($changedWslConfig) {
    Write-Host 'Die neue .wslconfig gilt erst nach einem Neustart von WSL: wsl --shutdown (beendet alle WSL-Sitzungen).'
}
Write-Host 'Nächste Schritte siehe README: install-font.ps1, danach install-admin.ps1 in einer Administrator-PowerShell.'
