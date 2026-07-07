# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L20    Show-Header
#   L46    Invoke-Engine
#   L57    Show-AnaliseRecomendacao
#   L88    Show-PerfisMenu
#   L115   Show-LimpezaManual
#   L140   Show-Logs
# ======================= END NAV INDEX =======================

# HUB CENTRAL - chamado pelo INICIAR.bat (ja elevado).

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "RamCommon.ps1")

$IsAdmin = Test-Admin   # Test-Admin vem do RamCommon
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
    $map = @{ "1"="WorkingSets"; "2"="ModifiedPageList"; "3"="Standby"; "4"="All"; "5"="Safe" }
    while ($true) {
        Write-Host "`n[LIMPEZA MANUAL]`n" -ForegroundColor Cyan
        Write-Host "  1 - Working Sets" -ForegroundColor Yellow
        Write-Host "  2 - Modified Page List" -ForegroundColor Yellow
        Write-Host "  3 - Standby List" -ForegroundColor Yellow
        Write-Host "  4 - All (1 -> 2 -> 3: Working Sets + System WS -> Modified -> Standby)" -ForegroundColor Yellow
        Write-Host "  5 - Safe (1 -> 2: Working Sets -> Modified; ideal antes de desligar)" -ForegroundColor Yellow
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
function Show-ResumoSemana {
    Show-Header
    Write-Host "`n[RESUMO DA SEMANA - ultimos 7 dias]`n" -ForegroundColor Cyan
    $csv = Join-Path $Global:RamLogDir "cleanup-history.csv"
    if (-not (Test-Path $csv)) { Write-Host "(sem historico ainda - nenhuma limpeza registrada)" -ForegroundColor Gray; Read-Host "`nEnter para voltar"; return }

    # Parse invariante: FreedGB/percent podem sair com virgula decimal em PT-BR.
    $inv = [Globalization.CultureInfo]::InvariantCulture
    function ToNum($s) { $v = 0.0; [void][double]::TryParse(("$s" -replace ',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$v); $v }

    $limite = (Get-Date).AddDays(-7)
    $rows = @(Import-Csv $csv | Where-Object {
        try { [datetime]::ParseExact($_.Timestamp, 's', $inv) -ge $limite } catch { $false }
    })
    if ($rows.Count -eq 0) { Write-Host "(nenhuma limpeza nos ultimos 7 dias)" -ForegroundColor Gray; Read-Host "`nEnter para voltar"; return }

    $freed = ($rows | ForEach-Object { ToNum $_.FreedGB } | Where-Object { $_ -gt 0 } | Measure-Object -Sum).Sum
    $peak  = ($rows | ForEach-Object { ToNum $_.BeforePercent } | Measure-Object -Maximum).Maximum
    $top   = $rows | Group-Object Action | Sort-Object Count -Descending | Select-Object -First 1
    Write-Host (" Limpezas         : {0}" -f $rows.Count) -ForegroundColor White
    Write-Host (" RAM liberada     : ~{0} GB (soma dos ganhos)" -f [math]::Round([double]$freed, 2)) -ForegroundColor Green
    Write-Host (" Pico de uso      : {0}%" -f [math]::Round([double]$peak, 1)) -ForegroundColor Yellow
    Write-Host (" Acao mais usada  : {0} ({1}x)" -f $top.Name, $top.Count) -ForegroundColor White
    Write-Host (" Periodo          : {0}  ->  {1}" -f $rows[0].Timestamp, $rows[-1].Timestamp) -ForegroundColor DarkGray
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
    Write-Host "  6 - Configurar auto-execucao / agendamento / menu de contexto" -ForegroundColor White
    Write-Host "  7 - Testar sistema (RAMMap, permissoes, arquivos)" -ForegroundColor White
    Write-Host "  8 - Ver logs de hoje" -ForegroundColor White
    Write-Host "  9 - Editar configuracao (JSON)" -ForegroundColor White
    Write-Host "  R - Resumo da semana (limpezas, RAM liberada, pico)" -ForegroundColor White
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
        "R" { Show-ResumoSemana }
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
