<#
.SYNOPSIS
Legt die Aufgabe "WSL Ubuntu Autostart" an: WSL startet beim Hochfahren, ohne dass jemand angemeldet ist.

.DESCRIPTION
Die Aufgabe startet eine Minute nach dem Systemstart "wsl.exe -d <Distro> --exec sleep infinity" als der
angegebene Benutzer. Damit laufen systemd, Tailscale und mit linger auch die Benutzerdienste (Herdr-Server),
bevor sich jemand anmeldet. Damit das ohne Anmeldung geht, speichert Windows das Kennwort des Benutzers;
schtasks fragt es einmal ab. Braucht eine Administrator-PowerShell. Eine schon passende Aufgabe bleibt unverändert.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-admin.ps1 -WhatIf
Zeigt nur, was geschehen würde (geht auch ohne Administratorrechte).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interaktives Installationsskript: die Statuszeilen sind für die Konsole bestimmt.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$User = (whoami),
    [string]$TaskName = 'WSL Ubuntu Autostart'
)

$ErrorActionPreference = 'Stop'
# Aus WSL aufgerufen ist die Ausgabe umgeleitet; ohne UTF-8 kämen die Umlaute dort verstümmelt an.
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = [Text.Encoding]::UTF8 }
$arguments = "-d $Distro --exec sleep infinity"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    $action = $task.Actions | Select-Object -First 1
    $atBoot = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' }).Count -gt 0
    $withoutLogon = $task.Principal.LogonType -eq 'Password'
    # Windows speichert den Benutzer mal mit, mal ohne Domäne ("Benutzer" statt "DOMAIN\Benutzer").
    $sameUser = ($task.Principal.UserId -split '\\')[-1] -eq ($User -split '\\')[-1]
    if ($atBoot -and $withoutLogon -and $sameUser -and $action.Execute -eq 'wsl.exe' -and $action.Arguments -eq $arguments) {
        Write-Host ('  {0,-12} Aufgabe "{1}" (beim Systemstart, ohne Anmeldung)' -f 'unverändert', $TaskName)
        return
    }
    Write-Host ('  {0,-12} Aufgabe "{1}" weicht ab (Auslöser, Anmeldeart, Benutzer oder Befehl), wird ersetzt' -f 'abweichend', $TaskName)
}

$schtasksArgs = @('/create', '/tn', $TaskName, '/sc', 'onstart', '/delay', '0001:00', '/ru', $User, '/rp', '*', '/tr', "wsl.exe $arguments", '/f')
if (-not $PSCmdlet.ShouldProcess($TaskName, "schtasks.exe $($schtasksArgs -join ' ')")) {
    return
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Dieses Skript braucht Administratorrechte: PowerShell mit "Als Administrator ausführen" starten.'
}

Write-Host "Kennwort für $User eingeben (schtasks speichert es für den Start ohne Anmeldung):"
& schtasks.exe @schtasksArgs
if ($LASTEXITCODE -ne 0) {
    throw "schtasks.exe ist mit Code $LASTEXITCODE fehlgeschlagen"
}
Write-Host ('  {0,-12} Aufgabe "{1}"' -f 'angelegt', $TaskName)
