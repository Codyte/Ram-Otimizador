# ============================================================================
# NAV INDEX - Menu.ps1  (HUB CENTRAL - chamado pelo INICIAR.bat, ja elevado)
#   12-21   Bootstrap: dot-source RamCommon + deteccao de admin
#   23-58   Helpers: Show-Header (RAM/standby/tarefa), Invoke-Engine
#   60-89   Show-AnaliseRecomendacao (analise inteligente + aplicar)
#   91-116  Show-PerfisMenu (lista perfis pre-prontos e aplica)
#  118-142  Show-LimpezaManual (ordem: WS -> Modified -> Standby)
#  144-152  Show-Logs
#  157-206  Loop principal do menu (opcoes 0-9 + T tarefa 2o plano)
# ============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "RamCommon.ps1")

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
$IsAdmin = Test-Admin
$Engine  = Join-Path $ScriptDir "LimparRAM-Inteligente.ps1"

# ---------------------------------------------------------------------------
function Show-Header {
    Clear-Host
    $cfg = Read-RamConfig
    $mem = Get-MemoryStats
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "        LIMPADOR INTELIGENTE DE RAM  -  CENTRAL DE CONTROLE" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
    $adminTxt = if ($IsAdmin) { "ADMIN OK" } else { "SEM ADMIN (limpeza/agendamento desabilitados)" }
    $adminCol = if ($IsAdmin) { "Green" } else { "Red" }
    $sb    = Get-StandbyListMB
    $sbTxt = if ($sb -ge 0) { "{0}MB recuperaveis" -f $sb } else { "indisponivel" }
    $task  = Get-ScheduledTask -TaskName $Global:RamTaskName -ErrorAction SilentlyContinue
    $taskTxt = if (-not $task) { "nao configurada (opcao 6 cria)" }
               elseif ($task.State -eq 'Running')  { "RODANDO em 2o plano" }
               elseif ($task.State -eq 'Disabled') { "desativada" }
               else { "parada (T inicia)" }
    $taskCol = if ($task -and $task.State -eq 'Running') { "Green" }
               elseif ($task) { "Yellow" } else { "DarkGray" }
    Write-Host (" Perfil ativo : {0}" -f $cfg.Profile) -ForegroundColor White
    Write-Host (" RAM agora    : {0}GB / {1}GB ({2}%)" -f $mem.UsedMemoryGB, $mem.TotalMemoryGB, $mem.PercentUsed) -ForegroundColor White
    Write-Host (" Standby      : {0}" -f $sbTxt) -ForegroundColor White
    Write-Host (" Tarefa fundo : {0}" -f $taskTxt) -ForegroundColor $taskCol
    Write-Host (" Privilegios  : {0}" -f $adminTxt) -ForegroundColor $adminCol
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
}

function Invoke-Engine {
    param([hashtable]$Params)
    if (-not $IsAdmin) {
        Write-Host "[ERRO] Operacao requer Administrador. Reabra pelo INICIAR.bat (elevado)." -ForegroundColor Red
        Read-Host "Enter para voltar"; return
    }
    # Hashtable-splat: binda parametros nomeados/switches (array-splat passa posicional e falha).
    & $Engine @Params | Out-Null
}

# ---------------------------------------------------------------------------
function Show-AnaliseRecomendacao {
    Show-Header
    Write-Host "`n[ANALISE INTELIGENTE DO SISTEMA]`n" -ForegroundColor Cyan
    $rec = Get-RecommendedProfile
    $s   = $rec.System
    Write-Host (" Maquina   : {0} {1}" -f $s.Manufacturer, $s.Model) -ForegroundColor Gray
    Write-Host (" SO        : {0}" -f $s.OSName) -ForegroundColor Gray
    Write-Host (" RAM total : {0} GB   |  Nucleos: {1}" -f $s.TotalRAMGB, $s.CPUCores) -ForegroundColor Gray
    Write-Host (" Tipo      : {0}{1}{2}" -f `
        $(if ($s.IsServer) {"Servidor "} else {"Workstation "}),
        $(if ($s.IsPortable) {"Portatil "} else {"Desktop "}),
        $(if ($s.HasBattery) {"(com bateria)"} else {""})) -ForegroundColor Gray
    if ($rec.Heavy.Count -gt 0) {
        $hn = ($rec.Heavy | Select-Object -First 6 -ExpandProperty ProcessName) -join ", "
        Write-Host (" Pesados   : {0}" -f $hn) -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host (" >> PERFIL RECOMENDADO: {0}" -f $rec.Profile.ToUpper()) -ForegroundColor Green
    foreach ($r in $rec.Reasons) { Write-Host ("    - {0}" -f $r) -ForegroundColor Gray }
    $desc = (Get-RamProfiles)[$rec.Profile].Description
    Write-Host ("    {0}" -f $desc) -ForegroundColor DarkGray
    Write-Host ""
    $ans = Read-Host "Aplicar este perfil agora? (S/N)"
    if ($ans -match '^[sS]') {
        Apply-RamProfile -Name $rec.Profile | Out-Null
        Write-Host ("[OK] Perfil '{0}' aplicado." -f $rec.Profile) -ForegroundColor Green
    }
    Read-Host "Enter para voltar"
}

# ---------------------------------------------------------------------------
function Show-PerfisMenu {
    Show-Header
    Write-Host "`n[PERFIS PRE-PRONTOS]`n" -ForegroundColor Cyan
    $profiles = Get-RamProfiles
    $cfg = Read-RamConfig
    $keys = @($profiles.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $k = $keys[$i]
        $mark = if ($k -eq $cfg.Profile) { "*" } else { " " }
        Write-Host ("  {0}{1} - {2}" -f $mark, ($i + 1), $k) -ForegroundColor Yellow
        Write-Host ("       {0}" -f $profiles[$k].Description) -ForegroundColor DarkGray
        $p = $profiles[$k]
        Write-Host ("       limite {0} -> {1}  |  intervalo {2}s  cooldown {3}s" -f `
            (Format-UsageThreshold $p.ThresholdClean $p.ThresholdCleanGB),
            $p.CleanAction, $p.CheckIntervalSeconds, $p.CleanCooldownSeconds) -ForegroundColor DarkGray
    }
    Write-Host "`n  (* = perfil ativo)  0 - Voltar" -ForegroundColor Gray
    $sel = Read-Host "`nNumero do perfil"
    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $keys.Count) {
        $name = $keys[[int]$sel - 1]
        Apply-RamProfile -Name $name | Out-Null
        Write-Host ("[OK] Perfil '{0}' aplicado. Monitor ativo recarrega sozinho no proximo ciclo." -f $name) -ForegroundColor Green
        Read-Host "Enter para voltar"
    }
}

# ---------------------------------------------------------------------------
function Show-LimpezaManual {
    Show-Header
    $map = @{ "1"="WorkingSets"; "2"="ModifiedPageList"; "3"="Standby"; "4"="All"; "5"="SafeStrong"; "6"="WorkingStandby" }
    while ($true) {
        Write-Host "`n[LIMPEZA MANUAL]`n" -ForegroundColor Cyan
        Write-Host "  1 - Working Sets" -ForegroundColor Yellow
        Write-Host "  2 - Modified Page List" -ForegroundColor Yellow
        Write-Host "  3 - Standby List" -ForegroundColor Yellow
        Write-Host "  4 - TUDO (1 -> 2 -> 3: Working Sets + System WS -> Modified -> Standby)" -ForegroundColor Yellow
        Write-Host "  5 - Modified + Standby (2 -> 3: nao toca Working Sets, sem stutter)" -ForegroundColor Yellow
        Write-Host "  6 - Working + Standby (1 -> 3)" -ForegroundColor Yellow
        Write-Host "  0 - Voltar" -ForegroundColor Gray
        $sel = Read-Host "`nOpcao"

        if ($sel -eq "0") { return }
        if ($map.ContainsKey($sel)) {
            Invoke-Engine @{ Clean = $map[$sel] }
            Read-Host "`nEnter para continuar"
            Show-Header
            continue
        }
        Write-Host "Opcao invalida." -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
function Show-Logs {
    Show-Header
    $log = Join-Path $Global:RamLogDir "RAMMap_$(Get-Date -Format 'yyyy-MM-dd').log"
    Write-Host "`n[ULTIMAS 25 LINHAS DO LOG DE HOJE]" -ForegroundColor Cyan
    Write-Host $log -ForegroundColor DarkGray
    Write-Host ""
    if (Test-Path $log) { Get-Content $log -Tail 25 } else { Write-Host "(sem log hoje)" -ForegroundColor Gray }
    Read-Host "`nEnter para voltar"
}

# ---------------------------------------------------------------------------
# Loop principal
# ---------------------------------------------------------------------------
:menu while ($true) {
    Show-Header
    Write-Host ""
    Write-Host "  1 - Analisar sistema e recomendar perfil" -ForegroundColor White
    Write-Host "  2 - Escolher perfil pre-pronto (games, servidor 24/7, ...)" -ForegroundColor White
    Write-Host "  3 - Iniciar MONITOR continuo (primeiro plano)" -ForegroundColor White
    Write-Host "  4 - Limpeza manual rapida" -ForegroundColor White
    Write-Host "  5 - Dashboard ao vivo" -ForegroundColor White
    Write-Host "  6 - Configurar auto-execucao / agendamento" -ForegroundColor White
    Write-Host "  7 - Testar sistema (RAMMap, permissoes, arquivos)" -ForegroundColor White
    Write-Host "  8 - Ver logs de hoje" -ForegroundColor White
    Write-Host "  9 - Editar configuracao (JSON)" -ForegroundColor White
    Write-Host "  T - Iniciar/Parar a tarefa em 2o plano" -ForegroundColor White
    Write-Host "  0 - Sair" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "Escolha"

    switch ($choice) {
        "1" { Show-AnaliseRecomendacao }
        "2" { Show-PerfisMenu }
        "3" {
            Write-Host "`nIniciando monitor... Pressione Q para parar e voltar ao menu.`n" -ForegroundColor Green
            Invoke-Engine @{ Monitor = $true }
            Read-Host "`nMonitor encerrado. Enter para voltar"
        }
        "4" { Show-LimpezaManual }
        "5" { & (Join-Path $ScriptDir "Dashboard-RAM.ps1") }
        "6" { & (Join-Path $ScriptDir "Configurar-AutoExecucao.ps1") }
        "7" { & (Join-Path $ScriptDir "Teste-LimparRAM.ps1") }
        "8" { Show-Logs }
        "9" { notepad $Global:RamConfigPath }
        "T" {
            $t = Get-ScheduledTask -TaskName $Global:RamTaskName -ErrorAction SilentlyContinue
            if (-not $t) {
                Write-Host "`nNenhuma tarefa configurada ainda. Use a opcao 6 para criar." -ForegroundColor Yellow
            } elseif (-not $IsAdmin) {
                Write-Host "`n[ERRO] Iniciar/parar a tarefa requer Administrador." -ForegroundColor Red
            } elseif ($t.State -eq 'Running') {
                Stop-ScheduledTask -TaskName $Global:RamTaskName -ErrorAction SilentlyContinue
                Write-Host "`n[OK] Tarefa em 2o plano PARADA." -ForegroundColor Yellow
            } else {
                Start-ScheduledTask -TaskName $Global:RamTaskName -ErrorAction SilentlyContinue
                Write-Host "`n[OK] Tarefa em 2o plano INICIADA." -ForegroundColor Green
            }
            Read-Host "Enter para voltar"
        }
        "0" { Write-Host "Saindo..." -ForegroundColor Yellow; break menu }
        default { }
    }
}
