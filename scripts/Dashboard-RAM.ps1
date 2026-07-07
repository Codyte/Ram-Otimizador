# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L12    Show-RAMDashboard
#   L78    L
#   L79    S
# ======================= END NAV INDEX =======================

# Dashboard de monitoramento de RAM em tempo real

. (Join-Path $PSScriptRoot "RamCommon.ps1")

function Show-RAMDashboard {
    param([int]$IntervalSeconds = 5)

    $logDir  = $Global:RamLogDir
    $hbFile  = Join-Path $logDir "monitor-status.json"
    $prevCount = 0
    $bar = "========================================================"

    # Helpers de montagem de frame: L adiciona linha, S monta segmento colorido.
    # Definidos uma vez (nao por iteracao) — usam $script:frame no momento da chamada.
    function L { param([object[]]$Segs) $null = $script:frame.Add($Segs) }
    function S { param($t,$c='Gray') @{ T = [string]$t; C = $c } }

    try { [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            # ===== FASE 1: COLETA (tudo calculado ANTES de tocar a tela) =====
            $now = Get-Date -Format 'HH:mm:ss'
            $mem = Get-MemoryStats
            $FreeMemory  = $mem.FreeMemoryGB
            $TotalMemory = $mem.TotalMemoryGB
            $UsedMemory  = $mem.UsedMemoryGB
            $PercentUsed = $mem.PercentUsed
            $PercentFree = 100 - $PercentUsed
            $StandbyMB   = Get-StandbyListMB

            $BarLength = 50
            $UsedBars = [int][math]::Round($PercentUsed / 100 * $BarLength)
            $UsedBars = [math]::Max(0, [math]::Min($BarLength, $UsedBars))
            $UsedBar = "#" * $UsedBars
            $FreeBar = "-" * ($BarLength - $UsedBars)
            if     ($PercentUsed -gt 95) { $BarColor='DarkRed'; $St='[CRITICO]' }
            elseif ($PercentUsed -gt 85) { $BarColor='Red';     $St='[URGENTE]' }
            elseif ($PercentUsed -gt 70) { $BarColor='Yellow';  $St='[MODERADO]' }
            else                         { $BarColor='Green';   $St='[OK]' }

            # WorkingSet64: o WorkingSet (int32) estoura em processos >2GB e o
            # filtro -gt 0 derrubava justo os maiores consumidores do top-5.
            $TopProcesses = Get-Process | Where-Object { $_.WorkingSet64 -gt 0 } |
                Sort-Object WorkingSet64 -Descending | Select-Object -First 5

            $hb = $null
            if (Test-Path $hbFile) { try { $hb = Get-Content $hbFile -Raw | ConvertFrom-Json } catch {} }

            # Heartbeat obsoleto (monitor morto a forca deixa o json orfao):
            # sem atualizacao ha >3min ou PID inexistente -> nao confiar nele.
            $hbStale = $false
            if ($hb) {
                try {
                    $hbAge   = ((Get-Date) - [datetime]$hb.UpdatedAt).TotalSeconds
                    $hbAlive = [bool](Get-Process -Id $hb.PID -ErrorAction SilentlyContinue)
                    $hbStale = ($hbAge -gt 180) -or (-not $hbAlive)
                } catch { $hbStale = $true }
            }

            $Task = $null; $LastRun = $null
            try {
                $Task = Get-ScheduledTask -TaskName $Global:RamTaskName -ErrorAction SilentlyContinue
                if ($Task) { $LastRun = ($Task | Get-ScheduledTaskInfo).LastRunTime }
            } catch {}

            # Log do dia recalculado por frame (o dashboard pode virar a meia-noite aberto)
            $logFile = Join-Path $logDir "RAMMap_$(Get-Date -Format 'yyyy-MM-dd').log"
            $LastLog = $null
            if (Test-Path $logFile) {
                $LastLog = Get-Content $logFile -Tail 1 -ErrorAction SilentlyContinue
                if ($LastLog -and $LastLog.Length -gt 64) { $LastLog = $LastLog.Substring(0,64) + "..." }
            }

            # ===== FASE 2: MONTAR FRAME (linhas com segmentos coloridos) =====
            $script:frame = New-Object System.Collections.ArrayList

            L (S $bar 'Cyan')
            L (S "        DASHBOARD DE MONITORAMENTO DE RAM" 'Cyan')
            L (S "        Atualizado: $now" 'Cyan')
            L (S $bar 'Cyan')
            L (S "")
            L (S "Barra de Uso:" 'White')
            L @( (S "$St [" 'White'), (S $UsedBar $BarColor), (S $FreeBar 'DarkGray'), (S ("] {0}%" -f [math]::Round($PercentUsed,1)) 'Gray') )
            L (S "")
            L (S "ESTATISTICAS:" 'Cyan')
            L (S ("  Memoria Total:    {0} GB" -f [math]::Round($TotalMemory,2)) 'Gray')
            L (S ("  Memoria Usada:    {0} GB ({1}%)" -f [math]::Round($UsedMemory,2), [math]::Round($PercentUsed,2)) 'Yellow')
            L (S ("  Memoria Livre:    {0} GB ({1}%)" -f [math]::Round($FreeMemory,2), [math]::Round($PercentFree,2)) 'Green')
            $sbTxt = if ($StandbyMB -ge 0) { "{0} MB (recuperavel via limpeza)" -f $StandbyMB } else { "indisponivel" }
            L (S ("  Standby List:     {0}" -f $sbTxt) 'Gray')
            L (S "")
            L (S "TOP 5 PROCESSOS (Memoria):" 'Cyan')
            $rank = 1
            foreach ($proc in $TopProcesses) {
                $MemMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                L (S ("  {0}. {1} {2,10} MB" -f $rank, $proc.ProcessName.PadRight(22), $MemMB) 'Gray')
                $rank++
            }
            L (S "")
            L (S "STATUS DO MONITOR:" 'Cyan')
            # Fonte unica: heartbeat. (O check antigo por CommandLine nao via o
            # monitor iniciado pelo Menu, que roda in-process como Menu.ps1.)
            if ($hb -and -not $hbStale) { L (S ("  [OK] Monitor: ATIVO (PID {0})" -f $hb.PID) 'Green') }
            else                        { L (S "  [PAUSADO] Monitor: INATIVO" 'Yellow') }
            if ($hb -and $hbStale) {
                L (S "  [AVISO] Heartbeat desatualizado - monitor pode ter sido finalizado a forca" 'Yellow')
            } elseif ($hb) {
                $hbState = switch ("$($hb.State)") {
                    'Cleaning'     { 'LIMPANDO AGORA' }
                    'Cooldown'     { "cooldown ($($hb.CooldownRemainingSeconds)s restantes)" }
                    'WaitingRearm' { 'aguardando rearme (histerese)' }
                    'Skipped'      { 'standby baixo - limpeza dispensada' }
                    'Idle'         { 'ocioso (RAM abaixo do limite)' }
                    'Disabled'     { 'sem limite configurado' }
                    ''             { '-' }
                    default        { "$($hb.State)" }
                }
                L (S ("  Perfil: {0} | Estado: {1}" -f $hb.Profile, $hbState) 'Gray')
                L (S ("  Limpezas: {0} | Liberado: {1}GB" -f $hb.CleanCount, $hb.TotalFreedGB) 'Gray')
            }
            if ($Task) {
                L (S "  [OK] Tarefa agendada: CRIADA" 'Green')
                if ($LastRun) { L (S ("     Ultima execucao: {0}" -f (Get-Date $LastRun -Format 'dd/MM HH:mm:ss')) 'Gray') }
            } else { L (S "  [PAUSADO] Tarefa agendada: NAO CRIADA" 'Yellow') }
            if ($LastLog) { L (S "  [OK] Logs: SENDO REGISTRADOS" 'Green'); L (S ("     {0}" -f $LastLog) 'DarkGray') }
            else          { L (S "  [PAUSADO] Logs: AINDA NAO CRIADOS" 'Yellow') }
            L (S "")
            L (S "RECOMENDACOES:" 'Cyan')
            if     ($PercentUsed -gt 95) { L (S "  [CRITICO] RAM acima de 95% - feche apps ou limpe (opcao 4 do menu)" 'Red') }
            elseif ($PercentUsed -gt 85) { L (S "  [ATENCAO] RAM alta - limpeza automatica entra se monitor ativo" 'Yellow') }
            elseif ($PercentUsed -gt 70) { L (S "  [INFO] RAM moderada - monitoramento em dia" 'Gray') }
            else                         { L (S "  [OK] RAM em otimo nivel" 'Green') }
            L (S "")
            L (S $bar 'DarkGray')
            L (S ("Atualizando em {0}s... [Q] volta ao menu" -f $IntervalSeconds) 'DarkGray')
            L (S $bar 'DarkGray')

            # ===== FASE 3: PINTAR (cursor home + padding; sem flicker) =====
            $w = 80; try { $w = [Console]::WindowWidth } catch {}
            # NB: nao usar $home aqui - e variavel reservada (read-only) do PowerShell.
            try { [Console]::SetCursorPosition(0, 0) } catch { Clear-Host }
            foreach ($line in $script:frame) {
                $len = 0
                foreach ($s in $line) { Write-Host $s.T -NoNewline -ForegroundColor $s.C; $len += $s.T.Length }
                $pad = $w - 1 - $len
                if ($pad -gt 0) { Write-Host (' ' * $pad) -NoNewline }
                Write-Host ''
            }
            # Apaga linhas remanescentes de um frame anterior maior
            for ($x = $script:frame.Count; $x -lt $prevCount; $x++) { Write-Host (' ' * ($w - 1)) }
            $prevCount = $script:frame.Count

            # ===== FASE 4: ESPERAR (polling de teclado; Q/Esc volta) =====
            $waited = 0.0
            while ($waited -lt $IntervalSeconds) {
                try {
                    if ([Console]::KeyAvailable) {
                        $k = [Console]::ReadKey($true)
                        if ($k.Key -eq 'Q' -or $k.Key -eq 'Escape') { return }
                    }
                } catch {}
                Start-Sleep -Milliseconds 200
                $waited += 0.2
            }
        }
    }
    finally { try { [Console]::CursorVisible = $true } catch {} }
}

# Menu principal
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   DASHBOARD DE MONITORAMENTO DE RAM" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Escolha intervalo de atualizacao:" -ForegroundColor Yellow
Write-Host "1 - A cada 1 segundo (maximo detalhe)" -ForegroundColor Gray
Write-Host "2 - A cada 5 segundos (padrao)" -ForegroundColor Gray
Write-Host "3 - A cada 10 segundos (menor CPU)" -ForegroundColor Gray
Write-Host "4 - Personalizado" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "Opcao"

$interval = 5
switch ($choice) {
    "1" { $interval = 1 }
    "2" { $interval = 5 }
    "3" { $interval = 10 }
    "4" {
        $rawInterval = Read-Host "Segundos"
        $parsedInterval = 0
        if ([int]::TryParse($rawInterval, [ref]$parsedInterval) -and $parsedInterval -ge 1) {
            $interval = $parsedInterval
        } else {
            $interval = 5
        }
    }
    default { $interval = 5 }
}

Write-Host "Iniciando dashboard com intervalo de $interval segundos..." -ForegroundColor Green
Write-Host "Pressione Q ou Esc para voltar" -ForegroundColor Yellow
Start-Sleep -Seconds 2

Show-RAMDashboard -IntervalSeconds $interval
