# ====================================================================
#  Instalacao 1-linha do Ram-Otimizador:
#    irm https://raw.githubusercontent.com/Codyte/Ram-Otimizador/master/install.ps1 | iex
#  Baixa a ultima tag do GitHub, instala em %LOCALAPPDATA%\Ram-Otimizador
#  (atualizacao preserva config/ e logs/) e abre o painel (INICIAR.bat).
# ====================================================================
$ErrorActionPreference = 'Stop'
# TLS 1.2 p/ Windows PowerShell 5.1 antigo (senao Invoke-WebRequest falha no GitHub)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

$repo = 'Codyte/Ram-Otimizador'
$dest = Join-Path $env:LOCALAPPDATA 'Ram-Otimizador'
$zip  = Join-Path $env:TEMP 'Ram-Otimizador.zip'
$tmp  = Join-Path $env:TEMP 'Ram-Otimizador-extract'

$tag = (Invoke-RestMethod "https://api.github.com/repos/$repo/tags")[0].name
Write-Host "Baixando Ram-Otimizador $tag..." -ForegroundColor Cyan
Invoke-WebRequest "https://github.com/$repo/archive/refs/tags/$tag.zip" -OutFile $zip

if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip -DestinationPath $tmp -Force
$src = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName

# Copia por cima (sem apagar $dest): config/ e logs/ do usuario ficam intactos
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $src '*') $dest -Recurse -Force
Remove-Item $zip, $tmp -Recurse -Force

Write-Host "Instalado em $dest" -ForegroundColor Green
Write-Host "Abrindo o painel (vai pedir Administrador via UAC)..."
Start-Process (Join-Path $dest 'INICIAR.bat')
