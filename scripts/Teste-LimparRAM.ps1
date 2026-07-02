# Script de teste para validar configuracao do sistema de limpeza de RAM

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "RamCommon.ps1")

Write-Host "=== TESTE DO SISTEMA DE LIMPEZA DE RAM ===" -ForegroundColor Cyan
Write-Host ""

# 1. Verificar privilegios
Write-Host "[1/5] Verificando privilegios de ADMIN..." -ForegroundColor Yellow
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[OK] Rodando como ADMIN" -ForegroundColor Green
} else {
    Write-Host "[ERRO] NAO esta rodando como ADMIN - RAMMap nao funcionara!" -ForegroundColor Red
    Write-Host "   Clique direito no PowerShell > Executar como administrador" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# 2. Verificar motores de limpeza (API nativa e/ou RAMMap)
Write-Host "[2/5] Verificando motores de limpeza..." -ForegroundColor Yellow
$NativeOk   = Initialize-NativeClean
$RAMMapPath = Resolve-RAMMap

if ($NativeOk) {
    Write-Host "[OK] Motor NATIVO disponivel (API do Windows, sem processo externo)" -ForegroundColor Green
} else {
    Write-Host "[AVISO] Motor nativo indisponivel neste contexto" -ForegroundColor Yellow
}
if ($RAMMapPath -and (Test-Path $RAMMapPath)) {
    Write-Host "[OK] RAMMap encontrado em:" -ForegroundColor Green
    Write-Host "   $RAMMapPath" -ForegroundColor Gray
} elseif ($NativeOk) {
    Write-Host "[INFO] RAMMap nao encontrado - sem problema, o motor nativo assume" -ForegroundColor Cyan
} else {
    Write-Host "[ERRO] Nenhum motor de limpeza disponivel (RAMMap ausente e API nativa falhou)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Passos para resolver:" -ForegroundColor Yellow
    Write-Host "1. Baixe em: https://learn.microsoft.com/sysinternals/downloads/rammap" -ForegroundColor Gray
    Write-Host "2. Copie RAMMap.exe para a pasta scripts deste projeto: $PSScriptRoot" -ForegroundColor Gray
    Write-Host "3. Execute este teste novamente" -ForegroundColor Gray
    exit 1
}

Write-Host ""

# 3. Verificar scripts
Write-Host "[3/5] Verificando arquivos necessarios..." -ForegroundColor Yellow
$FilesNeeded = @(
    (Join-Path $Global:RamScripts "LimparRAM-Inteligente.ps1"),
    $Global:RamConfigPath,
    (Join-Path $Global:RamScripts "Configurar-AutoExecucao.ps1"),
    (Join-Path $Global:RamRoot "INICIAR.bat"),
    (Join-Path $Global:RamRoot "docs\README.md")
)

$AllExist = $true
foreach ($File in $FilesNeeded) {
    if (Test-Path $File) {
        Write-Host "[OK] $(Split-Path $File -Leaf)" -ForegroundColor Green
    } else {
        Write-Host "[ERRO] $(Split-Path $File -Leaf)" -ForegroundColor Red
        $AllExist = $false
    }
}

if (-not $AllExist) {
    Write-Host ""
    Write-Host "[AVISO] Alguns arquivos estao faltando!" -ForegroundColor Red
    exit 1
}

Write-Host ""

# 4. Testar limpeza de RAM
Write-Host "[4/5] Teste de limpeza de RAM..." -ForegroundColor Yellow
Write-Host "Obtendo status atual..." -ForegroundColor Gray

$OS = Get-CimInstance Win32_OperatingSystem
$FreeMemory = $OS.FreePhysicalMemory / 1MB
$TotalMemory = $OS.TotalVisibleMemorySize / 1MB
$UsedMemory = $TotalMemory - $FreeMemory
$PercentUsed = ($UsedMemory / $TotalMemory) * 100

Write-Host "RAM Usada: $([math]::Round($UsedMemory, 2))GB / $([math]::Round($TotalMemory, 2))GB ($([math]::Round($PercentUsed, 1))%)" -ForegroundColor Gray

if ($PercentUsed -gt 70) {
    Write-Host ""
    Write-Host "Executando limpeza de Standby List..." -ForegroundColor Yellow

    try {
        if ($NativeOk) {
            if (-not (Invoke-NativeCleanStep -Step Standby)) { throw "API nativa falhou no passo Standby" }
        } else {
            & $RAMMapPath -Et
            if ($LASTEXITCODE -ne 0) { throw "RAMMap retornou ExitCode=$LASTEXITCODE" }
        }

        Start-Sleep -Seconds 1

        $OSAfter = Get-CimInstance Win32_OperatingSystem
        $FreeAfter = $OSAfter.FreePhysicalMemory / 1MB
        $UsedAfter = $TotalMemory - $FreeAfter
        $PercentAfter = ($UsedAfter / $TotalMemory) * 100

        $Freed = [math]::Round($UsedMemory - $UsedAfter, 2)

        Write-Host "[OK] Limpeza realizada!" -ForegroundColor Green
        Write-Host "   Antes:  $([math]::Round($UsedMemory, 2))GB ($([math]::Round($PercentUsed, 1))%)" -ForegroundColor Gray
        Write-Host "   Depois: $([math]::Round($UsedAfter, 2))GB ($([math]::Round($PercentAfter, 1))%)" -ForegroundColor Gray
        Write-Host "   Liberados: $($Freed)GB" -ForegroundColor Gray
    } catch {
        Write-Host "[ERRO] Erro ao executar RAMMap: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[INFO] RAM em uso < 70% - Pulando teste de limpeza" -ForegroundColor Cyan
}

Write-Host ""

# 5. Verificar logs
Write-Host "[5/5] Verificando pasta de logs..." -ForegroundColor Yellow
$LogDir = $Global:RamLogDir

if (Test-Path $LogDir) {
    Write-Host "[OK] Pasta de logs existe" -ForegroundColor Green
    $LogFiles = Get-ChildItem $LogDir -Filter "*.log" | Measure-Object
    Write-Host "   Total de logs: $($LogFiles.Count)" -ForegroundColor Gray
} else {
    Write-Host "[AVISO] Criando pasta de logs..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    Write-Host "[OK] Pasta criada" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "[SUCESSO] TESTE CONCLUIDO COM SUCESSO!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Proximos passos:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Para auto-execucao, execute:" -ForegroundColor Yellow
Write-Host "    .\Configurar-AutoExecucao.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Para monitoramento continuo, execute:" -ForegroundColor Yellow
Write-Host "    .\LimparRAM-Inteligente.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Leia as instrucoes em:" -ForegroundColor Yellow
Write-Host "    docs\README.md" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. Customize se necessario:" -ForegroundColor Yellow
Write-Host "    config\RamCleanerConfig.json" -ForegroundColor Cyan
Write-Host ""

Read-Host "Pressione Enter para fechar"
