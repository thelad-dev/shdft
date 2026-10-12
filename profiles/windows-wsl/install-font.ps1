<#
.SYNOPSIS
Installiert Hack Nerd Font v3.4.0 für den aktuellen Windows-Benutzer (ohne Administratorrechte).

.DESCRIPTION
Lädt Hack.zip aus dem Release v3.4.0 von github.com/ryanoasis/nerd-fonts, prüft die SHA-256-Summe,
legt die vier Schnitte Regular, Bold, Italic und BoldItalic unter %LOCALAPPDATA%\Microsoft\Windows\Fonts ab
und trägt sie in HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts ein.
Bereits installierte Schnitte mit passender Prüfsumme bleiben unverändert; dann wird nichts heruntergeladen.
WezTerm sieht die Schrift nach einem Neustart.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-font.ps1 -WhatIf
Zeigt nur, was geschehen würde.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interaktives Installationsskript: die Statuszeilen sind für die Konsole bestimmt.')]
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
# Aus WSL aufgerufen ist die Ausgabe umgeleitet; ohne UTF-8 kämen die Umlaute dort verstümmelt an.
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = [Text.Encoding]::UTF8 }
$zipUrl = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Hack.zip'
$zipSha256 = '8CA33A60C791392D872B80D26C42F2BFA914A480F9EB2D7516D9F84373C36897'
# Prüfsummen der einzelnen Schnitte aus genau diesem Archiv.
$fonts = [ordered]@{
    'Regular'    = '7E6B5D86BAEE613984B10CEF14C8D6AEE86C976A3D1CBD87ABFFD424D6EC4C64'
    'Bold'       = '7FB835CBD3273D509868DCD4E03EAB3DC98679AC0BDFFD52EF23411244396082'
    'Italic'     = 'B65EDFCBDCE25A6F359B6AD129F51FC0B7C59E4893676FC3B75A4F49E3A12B18'
    'BoldItalic' = '1A6FDC79F82BEB3CA3A0BC2088568A24B094B55F0F93CBF9731BF8E1EDE85D6B'
}
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$registryKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

# Get-FileHash ist in Windows PowerShell 5.1 eine Skriptfunktion, die unter -WhatIf nichts liefert;
# der Vergleich muss im Trockenlauf aber laufen, deshalb direkt über .NET.
function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose() }
}

function Test-FontInstalled([string]$Style, [string]$Sha256) {
    $file = Join-Path $fontDir "HackNerdFont-$Style.ttf"
    $value = (Get-ItemProperty -Path $registryKey -ErrorAction SilentlyContinue)."Hack Nerd Font $Style (TrueType)"
    return (Test-Path -LiteralPath $file) -and $value -eq $file -and (Get-Sha256 $file) -eq $Sha256
}

$missing = @($fonts.Keys | Where-Object { -not (Test-FontInstalled $_ $fonts[$_]) })
Write-Host 'Hack Nerd Font v3.4.0:'
foreach ($style in $fonts.Keys) {
    if ($missing -notcontains $style) { Write-Host ('  {0,-12} HackNerdFont-{1}.ttf' -f 'unverändert', $style) }
}
if ($missing.Count -eq 0) {
    return
}
if (-not $PSCmdlet.ShouldProcess($fontDir, "Schnitte $($missing -join ', ') aus $zipUrl installieren")) {
    return
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('shdft-font-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $zip = Join-Path $work 'Hack.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zip
    $actual = (Get-Sha256 $zip)
    if ($actual -ne $zipSha256) {
        throw "Prüfsumme von Hack.zip stimmt nicht: erwartet $zipSha256, erhalten $actual"
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $work
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    foreach ($style in $missing) {
        $name = "HackNerdFont-$style.ttf"
        $source = Join-Path $work $name
        if ((Get-Sha256 $source) -ne $fonts[$style]) {
            throw "Prüfsumme von $name stimmt nicht"
        }
        $target = Join-Path $fontDir $name
        Copy-Item -LiteralPath $source -Destination $target -Force
        New-ItemProperty -Path $registryKey -Name "Hack Nerd Font $style (TrueType)" -Value $target -PropertyType String -Force | Out-Null
        Write-Host ('  {0,-12} {1}' -f 'installiert', $name)
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'WezTerm neu starten, damit die Schrift erscheint.'
