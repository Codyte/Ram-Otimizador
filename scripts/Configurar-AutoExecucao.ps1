# ============================================================================
# NAV INDEX - Configurar-AutoExecucao.ps1
#   Bootstrap + admin + paths (dot-source RamCommon)
#   Remove-ExistingTask / Confirm-SystemRAMMapEula (EULA do SYSTEM)
#   New-MonitorTask (monitor continuo no boot/logon - RECOMENDADO)
#   New-PeriodicTask (verificacao leve -Once a cada N min)
#   Remove-AutoExec (so o agendamento) / Show-TaskStatus
#   Get-MonitorProcesses / Invoke-FullCleanup (PARAR TUDO + limpar residuos)
#   Menu
# ============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "RamCommon.ps1")

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    Write-Host "[ERRO] Requer Administrador. Abra pelo INICIAR.bat (elevado)." -ForegroundColor Red
    Read-Host "Enter para fechar"; exit 1
}

$Engine   = Join-Path $ScriptDir "LimparRAM-Inteligente.ps1"
$EngineFull = [IO.Path]::GetFullPath($Engine)
$TaskName = "LimparRAM-Monitoramento"
$Desc     = "Limpeza inteligente de RAM (RAMMap)"

function Resolve-ScheduledPowerShell {
    $systemPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $systemPowerShell) { return $systemPowerShell }
    $cmd = Get-Command powershell.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return "powershell.exe"
}

$PowerShellExe = Resolve-ScheduledPowerShell

function Test-TaskRunsThisEngine {
    param([Parameter(Mandatory)]$Task)
    foreach ($action in @($Task.Actions)) {
        $args = "$($action.Arguments)"
        if ($args.IndexOf($EngineFull, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Remove-ExistingTask {
    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
}

# A tarefa roda como SYSTEM. RAMMap so funciona apos aceitar o EULA, e isso e
# por usuario (HKCU). O SYSTEM nunca aceitou -> em 2o plano a janela de licenca
# fica invisivel (sessao 0) e a limpeza nao acontece. Aqui (rodando elevado)
# pre-aceitamos o EULA na colmeia do SYSTEM (S-1-5-18).
function Confirm-SystemRAMMapEula {
    $key = 'Registry::HKEY_USERS\S-1-5-18\Software\Sysinternals\RAMMap'
    try {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name 'EulaAccepted' -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Host "[OK] EULA do RAMMap aceito para a conta SYSTEM (necessario p/ rodar em 2o plano)." -ForegroundColor Green
    } catch {
        Write-Host "[AVISO] Nao consegui aceitar o EULA do RAMMap p/ SYSTEM: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "        O monitor tentara aceitar sozinho na primeira limpeza." -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Modelo 1: MONITOR CONTINUO no boot+logon (recomendado)
# ---------------------------------------------------------------------------
function New-MonitorTask {
    Remove-ExistingTask
    Confirm-SystemRAMMapEula
    $action = New-ScheduledTaskAction -Execute $PowerShellExe `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Engine`" -Monitor"

    $trigStartup = New-ScheduledTaskTrigger -AtStartup
    $trigLogon   = New-ScheduledTaskTrigger -AtLogOn

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)         # sem limite (loop continuo)

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action `
            -Trigger @($trigStartup, $trigLogon) -Settings $settings -Principal $principal `
            -Description "$Desc (monitor continuo)" -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "[ERRO] Falha ao registrar tarefa: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    Write-Host "[OK] Tarefa criada: MONITOR CONTINUO" -ForegroundColor Green
    Write-Host "   - Inicia no boot e no logon, roda como SYSTEM, escondido, sem limite de tempo." -ForegroundColor Gray
    Write-Host "   - Reinicia sozinho ate 3x se falhar." -ForegroundColor Gray
    $ans = Read-Host "Iniciar agora tambem? (S/N)"
    if ($ans -match '^[sS]') { Start-ScheduledTask -TaskName $TaskName; Write-Host "[OK] Iniciado." -ForegroundColor Green }
}

# ---------------------------------------------------------------------------
# Modelo 2: verificacao periodica leve (-Once a cada N min)
# ---------------------------------------------------------------------------
function New-PeriodicTask {
    $minStr = Read-Host "Intervalo em minutos (padrao 5)"
    $min = 5; if ($minStr -match '^\d+$' -and [int]$minStr -ge 1) { $min = [int]$minStr }

    Remove-ExistingTask
    Confirm-SystemRAMMapEula
    $action = New-ScheduledTaskAction -Execute $PowerShellExe `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Engine`" -Once"

    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $min)
    $trigStartup = New-ScheduledTaskTrigger -AtStartup

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 4)

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action `
            -Trigger @($trigger, $trigStartup) -Settings $settings -Principal $principal `
            -Description "$Desc (periodico ${min}min)" -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "[ERRO] Falha ao registrar tarefa: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    Write-Host "[OK] Tarefa criada: VERIFICACAO PERIODICA a cada $min min." -ForegroundColor Green
    Write-Host "   - Cada execucao verifica e limpa uma vez, depois encerra (zero overhead em idle)." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
function Remove-AutoExec {
    Remove-ExistingTask
    try { Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "LimparRAM-Monitor" -Force -ErrorAction Stop } catch {}
    Write-Host "[OK] Auto-execucao removida." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Limpeza TOTAL do que roda em 2o plano: mata monitores, remove agendamentos e
# limpa residuos (entradas de inicializacao + heartbeat). Mantem config e logs.
# ---------------------------------------------------------------------------
# Processos powershell/pwsh rodando o engine (monitor/once), exceto ESTE processo
# (o menu roda no mesmo PID; nunca o matamos).
function Get-MonitorProcesses {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf($EngineFull, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $_.ProcessId -ne $PID
        }
}

function Invoke-FullCleanup {
    Write-Host "`n[LIMPEZA TOTAL DO SCRIPT]" -ForegroundColor Cyan
    Write-Host "Vai matar monitores em 2o plano, remover TODOS os agendamentos e limpar residuos." -ForegroundColor Gray
    Write-Host "Config e logs sao mantidos." -ForegroundColor DarkGray
    if ((Read-Host "Confirmar? (S/N)") -notmatch '^[sS]') { Write-Host "Cancelado." -ForegroundColor Yellow; return }

    # 1) Remover agendamentos PRIMEIRO (a nomeada + qualquer tarefa que rode o engine),
    #    p/ nao relancar um monitor entre o kill e a remocao.
    $removed = 0
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -eq $TaskName -or (Test-TaskRunsThisEngine $_)
    })
    foreach ($t in $tasks) {
        try {
            Stop-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            $removed++
        } catch { Write-Host "   [!] Falha ao remover tarefa '$($t.TaskName)': $($_.Exception.Message)" -ForegroundColor DarkYellow }
    }
    Write-Host ("   - Tarefas agendadas removidas: {0}" -f $removed) -ForegroundColor Green

    # 2) Remover entradas de inicializacao (Run) em HKCU e HKLM
    $runRemoved = 0
    foreach ($hive in 'HKCU:', 'HKLM:') {
        $path = "$hive\Software\Microsoft\Windows\CurrentVersion\Run"
        try {
            $props = Get-ItemProperty -Path $path -ErrorAction Stop
            foreach ($n in $props.PSObject.Properties.Name) {
                if ($n -like 'LimparRAM*' -or "$($props.$n)" -like '*LimparRAM-Inteligente.ps1*') {
                    Remove-ItemProperty -Path $path -Name $n -Force -ErrorAction SilentlyContinue
                    $runRemoved++
                }
            }
        } catch {}
    }
    if ($runRemoved) { Write-Host ("   - Entradas de inicializacao (Run) removidas: {0}" -f $runRemoved) -ForegroundColor Green }

    # 3) Matar processos de monitoramento (agora que nada os relanca)
    $killed = 0
    foreach ($p in @(Get-MonitorProcesses)) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $killed++ }
        catch { Write-Host "   [!] Nao consegui matar PID $($p.ProcessId): $($_.Exception.Message)" -ForegroundColor DarkYellow }
    }
    Write-Host ("   - Monitores em 2o plano encerrados: {0}" -f $killed) -ForegroundColor Green

    # 4) Matar RAMMap residual (normalmente sai sozinho, mas garante)
    $rk = 0
    Get-Process -Name 'RAMMap', 'RAMMap64' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_ | Stop-Process -Force -ErrorAction Stop; $rk++ } catch {}
    }
    if ($rk) { Write-Host ("   - Processos RAMMap encerrados: {0}" -f $rk) -ForegroundColor Green }

    # 5) Limpar heartbeat (senao o Dashboard mostra 'monitor rodando' fantasma)
    $hb = Join-Path $Global:RamLogDir 'monitor-status.json'
    if (Test-Path $hb) { Remove-Item $hb -Force -ErrorAction SilentlyContinue; Write-Host "   - Heartbeat (monitor-status.json) removido." -ForegroundColor Green }

    Write-Host "`n[OK] Limpeza total concluida - sem monitores nem agendamentos residuais." -ForegroundColor Green
}

function Show-TaskStatus {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { Write-Host "Nenhuma tarefa configurada." -ForegroundColor Yellow; return }
    $info = $t | Get-ScheduledTaskInfo
    Write-Host "Tarefa     : $TaskName" -ForegroundColor Cyan
    Write-Host "Estado     : $($t.State)" -ForegroundColor Gray
    Write-Host "Descricao  : $($t.Description)" -ForegroundColor Gray
    Write-Host "Ultima exec: $($info.LastRunTime)  (resultado $($info.LastTaskResult))" -ForegroundColor Gray
    Write-Host "Proxima    : $($info.NextRunTime)" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
Write-Host "=== CONFIGURADOR DE AUTO-EXECUCAO ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1 - Monitor continuo no boot (RECOMENDADO p/ desktop/games)" -ForegroundColor Yellow
Write-Host "  2 - Verificacao periodica leve a cada N min (bom p/ servidor)" -ForegroundColor Yellow
Write-Host "  3 - Ver status da tarefa" -ForegroundColor Yellow
Write-Host "  4 - Remover auto-execucao (so o agendamento)" -ForegroundColor Red
Write-Host "  5 - PARAR TUDO e limpar residuos (mata monitores + remove agendamentos)" -ForegroundColor Red
Write-Host "  0 - Cancelar" -ForegroundColor Gray
Write-Host ""
switch (Read-Host "Opcao") {
    "1" { New-MonitorTask }
    "2" { New-PeriodicTask }
    "3" { Show-TaskStatus }
    "4" { Remove-AutoExec }
    "5" { Invoke-FullCleanup }
    default { Write-Host "Cancelado." -ForegroundColor Yellow }
}
Write-Host ""
Read-Host "Enter para fechar"
