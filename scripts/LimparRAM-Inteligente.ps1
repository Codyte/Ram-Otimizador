# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L57    Write-Log
#   L72    Confirm-RAMMapEula
#   L84    Invoke-RAMClean
#   L148   Invoke-RAMMapStep
#   L238   Invoke-CleanTracked
#   L254   Restore-CleanState
#   L263   Save-CleanState
#   L274   Write-Heartbeat
#   L308   Write-CycleLog
#   L318   Test-MemoryAndClean
#   L415   Wait-MonitorInterval
#   L434   Start-RAMMonitor
#   L508   Assert-Admin
#   L519   Show-Status
#   L551   Sem params: este script e o motor, nao a interface -------------------
# ======================= END NAV INDEX =======================

[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName = 'Monitor')]
    [switch]$Monitor,                       # Loop continuo (uso agendado)

    [Parameter(ParameterSetName = 'Once')]
    [switch]$Once,                          # Uma verificacao+limpeza e sai

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,                        # So mostra status (nao precisa admin)

    [Parameter(ParameterSetName = 'Clean')]
    [ValidateSet("Standby", "WorkingSets", "SystemWorkingSets", "ModifiedPageList", "Safe", "SafeStrong", "All")]
    [string]$Clean                          # Limpeza manual direta de um tipo
)

$ErrorActionPreference = 'Stop'

# Biblioteca compartilhada: paths portateis ($Global:Ram*), schema + leitura de
# config, metricas de memoria e deteccao de processos pesados. Fonte unica de
# verdade - este script nao reimplementa mais nada disso (antes era duplicado).
. (Join-Path $PSScriptRoot "RamCommon.ps1")

$ConfigPath    = $Global:RamConfigPath
$HeartbeatPath = Join-Path $Global:RamLogDir "monitor-status.json"
$RAMMapPath    = Resolve-RAMMap
if (-not $RAMMapPath) { $RAMMapPath = Join-Path $PSScriptRoot "RAMMap.exe" }  # default p/ msg de erro

$Config = Read-RamConfig
$script:RunMode = $PSCmdlet.ParameterSetName

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Delegado ao Write-RamLog (RamCommon), que calcula o arquivo do dia POR
# CHAMADA: monitor 24/7 vira a meia-noite sem prender o log no dia do boot.
# Aqui so injeta o LogLevel corrente da config (recarregavel em runtime).
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-RamLog -Message $Message -Level $Level -MinLevel $Config.LogLevel
}

# ---------------------------------------------------------------------------
# Execucao de limpeza
# ---------------------------------------------------------------------------
# RAMMap (Sysinternals) so roda depois que o EULA e aceito, e isso e gravado
# POR USUARIO em HKCU. Em 2o plano a tarefa roda como SYSTEM, que nunca aceitou
# o EULA -> a janela de licenca aparece (invisivel na sessao 0) e o RAMMap NAO
# executa a limpeza. Aqui aceitamos o EULA do usuario ATUAL (seja o admin
# interativo ou o SYSTEM), o que resolve o caso de fundo. Cada processo escreve
# o proprio HKCU, entao nao exige permissao cruzada.
$script:EulaEnsured = $false
function Confirm-RAMMapEula {
    if ($script:EulaEnsured) { return }
    try {
        if (Set-RAMMapEulaKey 'HKCU:\Software\Sysinternals\RAMMap') {
            Write-Log "EULA do RAMMap aceito automaticamente para este usuario (necessario p/ rodar em 2o plano/SYSTEM)." "INFO"
        }
        $script:EulaEnsured = $true
    } catch {
        Write-Log "Nao foi possivel aceitar o EULA do RAMMap automaticamente: $_" "WARNING"
    }
}

function Invoke-RAMClean {
    param(
        [ValidateSet("Standby", "WorkingSets", "SystemWorkingSets", "ModifiedPageList", "Safe", "SafeStrong", "All")]
        [string]$Type = "Standby"
    )

    # Passos elementares na ordem CORRETA: primeiro apara os Working Sets
    # (paginas sujas vao p/ a Modified List, limpas p/ a Standby), depois
    # descarrega a Modified Page List (grava no pagefile -> paginas viram
    # standby) e SO ENTAO esvazia a Standby List, liberando tudo de uma vez.
    # Purgar a standby NAO gera paginas modified (standby e cache limpo, ja
    # gravado em disco), entao nao ha risco de loop.
    $Steps = switch ($Type) {
        "Standby"           { @("Standby") }
        "WorkingSets"       { @("WorkingSets") }
        "SystemWorkingSets" { @("SystemWorkingSets") }
        "ModifiedPageList"  { @("ModifiedPageList") }
        # Safe: preparo p/ desligar - descarrega Working Sets e grava a Modified
        # List no disco (1 -> 2), sem purgar a Standby (inutil antes de shutdown).
        "Safe"              { @("WorkingSets", "ModifiedPageList") }
        # SafeStrong: libera forte SEM tocar nos Working Sets (sem stutter em
        # jogo/servidor). So Modified + Standby.
        "SafeStrong"        { @("ModifiedPageList", "Standby") }
        "All"               { @("WorkingSets", "SystemWorkingSets", "ModifiedPageList", "Standby") }
    }

    # Motor: API nativa do Windows (sem processo externo, sem EULA) ou RAMMap,
    # conforme CleanEngine (Auto prefere o nativo e cai p/ RAMMap se faltar
    # ou se o nativo falhar em runtime - $script:NativeBroken).
    $useNative = switch ("$($Config.CleanEngine)") {
        'Native' { $true }
        'RAMMap' { $false }
        default  { (-not $script:NativeBroken) -and (Initialize-NativeClean) }
    }
    if ($useNative -and -not (Initialize-NativeClean)) {
        Write-Log "Motor nativo indisponivel (sem privilegios de admin?); tentando RAMMap." "WARNING"
        $useNative = $false
    }
    if (-not $useNative) {
        if (-not (Test-Path $RAMMapPath)) {
            if (Initialize-NativeClean) {
                Write-Log "RAMMap.exe nao encontrado; usando o motor nativo." "WARNING"
                $useNative = $true
            } else {
                Write-Log "Nenhum motor disponivel: RAMMap ausente em '$RAMMapPath' e API nativa indisponivel." "ERROR"
                return $false
            }
        } else {
            Confirm-RAMMapEula   # garante EULA aceito antes de invocar o RAMMap
        }
    }
    $engineName = if ($useNative) { "Nativo" } else { "RAMMap" }

    # Flags REAIS do RAMMap CLI (Rammap -E[wsmt]): -Em -Ew -Es -Et
    $RAMMapFlag = @{ ModifiedPageList = "-Em"; WorkingSets = "-Ew"; SystemWorkingSets = "-Es"; Standby = "-Et" }

    try {
        $MemBefore     = Get-MemoryStats
        $StandbyBefore = Get-StandbyListMB
        $StepDelay     = if ($Config.StepDelayMs -ge 0) { [int]$Config.StepDelayMs } else { 400 }
        $StepTimeoutMs = 30000

        Write-Log "Iniciando limpeza (Tipo: $Type, motor: $engineName, passos: $($Steps -join ' > ')) - RAM: $($MemBefore.PercentUsed)% | Standby: ${StandbyBefore}MB" "INFO"

        function Invoke-RAMMapStep {
            param([string]$StepName)
            $Arg = $RAMMapFlag[$StepName]
            $proc = Start-Process -FilePath $RAMMapPath -ArgumentList $Arg -NoNewWindow -PassThru
            if (-not $proc.WaitForExit($StepTimeoutMs)) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                throw "RAMMap timeout apos $($StepTimeoutMs / 1000)s no passo '$Arg'"
            }
            $proc.Refresh()
            $exitCode = $null
            try { $exitCode = $proc.ExitCode } catch {}
            if ($null -ne $exitCode -and $exitCode -ne 0) {
                throw "RAMMap retornou ExitCode=$exitCode no passo '$Arg'"
            }
            if ($null -eq $exitCode) {
                Write-Log "RAMMap nao informou ExitCode no passo '$Arg'; processo encerrou dentro do timeout." "DEBUG"
            }
        }

        $first = $true
        foreach ($Step in $Steps) {
            # Delay ENTRE passos: deixa as paginas migrarem (ex: modified -> standby)
            # antes do passo seguinte, tornando a limpeza mais eficaz.
            if (-not $first -and $StepDelay -gt 0) { Start-Sleep -Milliseconds $StepDelay }
            if ($useNative) {
                if (-not (Invoke-NativeCleanStep -Step $Step)) {
                    if ("$($Config.CleanEngine)" -eq 'Native' -or -not (Test-Path $RAMMapPath)) {
                        throw "API nativa falhou no passo '$Step'"
                    }
                    # Auto: auto-recuperacao - termina esta limpeza (e as proximas)
                    # com o RAMMap em vez de abortar, e nao insiste mais no nativo.
                    $script:NativeBroken = $true
                    $useNative  = $false
                    $engineName = "RAMMap"
                    Confirm-RAMMapEula
                    Write-Log "API nativa falhou no passo '$Step' - caindo para o RAMMap." "WARNING"
                    Invoke-RAMMapStep -StepName $Step
                }
            } else {
                Invoke-RAMMapStep -StepName $Step
            }
            $first = $false
        }
        Start-Sleep -Milliseconds 500

        $MemAfter     = Get-MemoryStats
        $StandbyAfter = Get-StandbyListMB
        $FreedGB      = [math]::Round($MemBefore.UsedMemoryGB - $MemAfter.UsedMemoryGB, 2)

        # Numeros podem sair negativos (apps alocando RAM durante a limpeza);
        # nao imprimir "Liberados ~-0.36GB", que le como erro.
        $freedTxt = if ($FreedGB -ge 0) { "Liberados ~${FreedGB}GB" }
                    else { "Uso subiu $([math]::Abs($FreedGB))GB durante a limpeza" }
        $standbyTxt = if ($StandbyBefore -lt 0 -or $StandbyAfter -lt 0) { "standby ?" }
                      else {
                          $drop = $StandbyBefore - $StandbyAfter
                          if ($drop -ge 0) { "standby -${drop}MB" } else { "standby +$([math]::Abs($drop))MB" }
                      }
        Write-Log "Limpeza OK! $freedTxt ($standbyTxt) | RAM agora: $($MemAfter.PercentUsed)%" "INFO"
        $script:LastFreedGB = if ($FreedGB -gt 0) { $FreedGB } else { 0 }

        # Historico acumulado de eficacia (os contadores da sessao morrem com o
        # monitor; o CSV permite avaliar o perfil ao longo do tempo).
        # Interpolacao (nao -f): numeros saem com ponto decimal em qualquer locale.
        try {
            $histPath = Join-Path $Global:RamLogDir "cleanup-history.csv"
            if (-not (Test-Path $histPath)) {
                Add-Content -Path $histPath -Value "Timestamp,Mode,Action,Engine,BeforePercent,AfterPercent,FreedGB,StandbyBeforeMB,StandbyAfterMB"
            }
            Add-Content -Path $histPath -Value "$(Get-Date -Format 's'),$($script:RunMode),$Type,$engineName,$($MemBefore.PercentUsed),$($MemAfter.PercentUsed),$FreedGB,$StandbyBefore,$StandbyAfter"
        } catch {}
        return $true
    }
    catch {
        Write-Log "Erro na limpeza (motor $engineName): $_" "ERROR"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Decisao: quando e o que limpar (com cooldown + histerese)
# ---------------------------------------------------------------------------
$script:LastCleanTime = [datetime]::MinValue
$script:CleanCount    = 0
$script:TotalFreedGB  = 0.0
$script:LastFreedGB   = 0.0
$script:StartTime     = Get-Date
$script:CleanArmed    = $true
$script:NativeBroken  = $false   # nativo falhou em runtime -> Auto passa a usar RAMMap

function Invoke-CleanTracked {
    param([string]$Type)
    if (Invoke-RAMClean -Type $Type) {
        $script:LastCleanTime = Get-Date
        $script:CleanCount++
        $script:TotalFreedGB += $script:LastFreedGB
        return $true
    }
    return $false
}

# Estado persistido entre execucoes -Once (tarefa periodica). Sem isso cada
# execucao esquece cooldown e histerese e limpa TODA vez que estiver acima do
# limite, ignorando o anti-thrashing.
$CleanStatePath = Join-Path $Global:RamLogDir "clean-state.json"

function Restore-CleanState {
    if ($script:RunMode -ne 'Once') { return }
    try {
        $st = Get-Content $CleanStatePath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($st.LastCleanAt) { $script:LastCleanTime = [datetime]$st.LastCleanAt }
        if ($null -ne $st.CleanArmed) { $script:CleanArmed = [bool]$st.CleanArmed }
    } catch {}
}

function Save-CleanState {
    if ($script:RunMode -ne 'Once') { return }
    try {
        [pscustomobject]@{
            LastCleanAt = if ($script:LastCleanTime -ne [datetime]::MinValue) { $script:LastCleanTime.ToString('s') } else { $null }
            CleanArmed  = $script:CleanArmed
        } | ConvertTo-Json | Out-File $CleanStatePath -Encoding UTF8 -Force
    } catch {}
}

# Heartbeat: estado ao vivo p/ o Dashboard/Menu lerem
function Write-Heartbeat {
    param(
        [hashtable]$Stats,
        [int]$StandbyMB,
        [string]$State = "Idle",
        [int]$CooldownRemainingSeconds = 0
    )
    if ($script:RunMode -ne 'Monitor') { return }
    try {
        [pscustomobject]@{
            PID          = $PID
            Mode         = $script:RunMode
            State        = $State
            Profile      = $Config.Profile
            UpdatedAt    = (Get-Date).ToString('s')
            StartedAt    = $script:StartTime.ToString('s')
            PercentUsed  = $Stats.PercentUsed
            UsedGB       = $Stats.UsedMemoryGB
            TotalGB      = $Stats.TotalMemoryGB
            StandbyMB    = $StandbyMB
            CleanCount   = $script:CleanCount
            TotalFreedGB = [math]::Round($script:TotalFreedGB, 2)
            CleanArmed   = $script:CleanArmed
            CooldownRemainingSeconds = $CooldownRemainingSeconds
            LastCleanAt  = if ($script:LastCleanTime -ne [datetime]::MinValue) { $script:LastCleanTime.ToString('s') } else { $null }
        } | ConvertTo-Json | Out-File $HeartbeatPath -Encoding UTF8 -Force
    } catch {}
}

# DEBUG de ciclo repetitivo: loga so quando o estado muda (ou a cada 20 ciclos,
# como sinal de vida). Sem isso, DEBUG grava as mesmas linhas a cada 30s e um
# dia de log passa de 400KB.
$script:LastCycleKey   = ''
$script:CyclesSinceLog = 0
function Write-CycleLog {
    param([string]$Key, [string]$Message)
    $script:CyclesSinceLog++
    if ($Key -ne $script:LastCycleKey -or $script:CyclesSinceLog -ge 20) {
        Write-Log $Message "DEBUG"
        $script:LastCycleKey   = $Key
        $script:CyclesSinceLog = 0
    }
}

function Test-MemoryAndClean {
    $Stats       = Get-MemoryStats
    $PercentUsed = $Stats.PercentUsed
    $StandbyMB   = Get-StandbyListMB
    $TotalGB     = $Stats.TotalMemoryGB

    # UM limite (hibrido %/GB de RAM usada) dispara UMA acao.
    $thr = Resolve-UsageThresholdPercent $Config.ThresholdClean $Config.ThresholdCleanGB $TotalGB
    $hyst = [math]::Max(0, [double]$Config.HysteresisPercent)

    $statsTxt = "RAM: $($Stats.UsedMemoryGB)GB / ${TotalGB}GB ($PercentUsed%) | Standby: ${StandbyMB}MB"

    if ($null -eq $thr) {
        Write-Heartbeat -Stats $Stats -StandbyMB $StandbyMB -State "Disabled"
        Write-CycleLog -Key 'disabled' -Message "$statsTxt | sem limite de limpeza configurado - monitor sem acao."
        return
    }

    # Histerese em BANDA: apos limpar, so nao repete enquanto a RAM ficar
    # oscilando perto do limite (entre thr-hyst e thr+hyst). Cair abaixo de
    # thr-hyst rearma (comportamento classico); subir alem de thr+hyst TAMBEM
    # rearma — sem isso, uma limpeza que nao derruba a RAM abaixo de thr-hyst
    # travava o monitor em WaitingRearm para sempre enquanto a RAM so subia
    # (visto em produção: RAM a 60% por horas sem nenhuma limpeza).
    $rearmAt     = [math]::Max(0, $thr - $hyst)
    $rearmHighAt = [math]::Min(100, $thr + $hyst)
    if (-not $script:CleanArmed) {
        if ($PercentUsed -le $rearmAt) {
            $script:CleanArmed = $true
            Write-Log "Histerese rearmada: RAM $PercentUsed% <= ${rearmAt}%." "DEBUG"
        } elseif ($PercentUsed -ge $rearmHighAt) {
            $script:CleanArmed = $true
            Write-Log "Histerese rearmada por ALTA: RAM $PercentUsed% >= ${rearmHighAt}% (subiu apos a limpeza; cooldown segue valendo)." "DEBUG"
        }
    }

    if ($PercentUsed -le $thr) {
        $state = if ($script:CleanArmed) { "Idle" } else { "WaitingRearm" }
        Write-Heartbeat -Stats $Stats -StandbyMB $StandbyMB -State $state
        Write-CycleLog -Key "ok|$state" -Message "$statsTxt | abaixo do limite (${thr}%). Rearme em <= ${rearmAt}%."
        return
    }

    if (-not $script:CleanArmed) {
        Write-Heartbeat -Stats $Stats -StandbyMB $StandbyMB -State "WaitingRearm"
        Write-CycleLog -Key 'waitrearm-high' -Message "$statsTxt | limite atingido (> ${thr}%) mas aguardando histerese rearmar (cair <= ${rearmAt}% ou subir >= ${rearmHighAt}%)."
        return
    }

    # Cooldown: evita thrashing (limpar repetido em segundos).
    $sinceLast = (Get-Date) - $script:LastCleanTime
    if ($sinceLast.TotalSeconds -lt $Config.CleanCooldownSeconds) {
        $remaining = [math]::Ceiling($Config.CleanCooldownSeconds - $sinceLast.TotalSeconds)
        Write-Heartbeat -Stats $Stats -StandbyMB $StandbyMB -State "Cooldown" -CooldownRemainingSeconds $remaining
        Write-CycleLog -Key 'cooldown' -Message "$statsTxt | limite atingido (> ${thr}%) mas em cooldown ($([int]$sinceLast.TotalSeconds)s/$($Config.CleanCooldownSeconds)s) - pulando"
        return
    }

    $Action = "$($Config.CleanAction)"
    if ([string]::IsNullOrWhiteSpace($Action)) { $Action = "All" }

    # Guarda anti-stutter: se um app pesado/jogo estiver aberto, evita esvaziar
    # Working Sets (All/Safe -> SafeStrong), poupando o jogo/servidor de engasgo.
    # Safe entra na guarda porque tambem apara Working Sets (default do dia a dia).
    if ($Config.EnableGameDetection -and $Action -in @("All", "Safe")) {
        $HeavyApps = @(Get-HeavyProcesses)
        if ($HeavyApps.Count -gt 0) {
            $names = ($HeavyApps | Select-Object -First 3 -ExpandProperty ProcessName) -join ", "
            Write-Log "[GAMING] App pesado ($names) aberto - usando SafeStrong (sem Working Sets) p/ evitar engasgo" "INFO"
            $Action = "SafeStrong"
        }
    }

    # A acao 'Standby' so compensa se houver standby suficiente p/ recuperar.
    if ($Action -eq "Standby" -and $StandbyMB -ge 0 -and $StandbyMB -lt $Config.MinStandbyMB) {
        Write-Heartbeat -Stats $Stats -StandbyMB $StandbyMB -State "Skipped"
        Write-CycleLog -Key 'skipped' -Message "$statsTxt | acima do limite mas Standby < $($Config.MinStandbyMB)MB - nao compensa limpar"
        return
    }

    Write-Heartbeat -Stats $Stats -StandbyMB $StandbyMB -State "Cleaning"
    Write-Log "[LIMPEZA] RAM $PercentUsed% > limite ${thr}% - executando acao '$Action'..." "WARNING"
    $script:LastCycleKey = ''   # apos limpar, o proximo estado ocioso loga na hora
    if (Invoke-CleanTracked -Type $Action) {
        $script:CleanArmed = $false
        Write-Heartbeat -Stats (Get-MemoryStats) -StandbyMB (Get-StandbyListMB) -State "WaitingRearm"
    } else {
        Write-Heartbeat -Stats $Stats -StandbyMB $StandbyMB -State "Error"
    }
}

# ---------------------------------------------------------------------------
# Loop principal
# ---------------------------------------------------------------------------
# Espera ate o proximo ciclo aceitando Q/Esc para encerrar LIMPO (Ctrl+C mata
# o menu inteiro que chamou este script). Em 2o plano (tarefa oculta/sessao 0)
# [Console]::KeyAvailable lanca excecao -> dorme o restante e segue o loop.
function Wait-MonitorInterval {
    param([int]$Seconds)
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        try {
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Q' -or $k.Key -eq 'Escape') { return $true }
            }
        } catch {
            $rest = ($end - (Get-Date)).TotalSeconds
            if ($rest -gt 0) { Start-Sleep -Seconds ([math]::Ceiling($rest)) }
            return $false
        }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Start-RAMMonitor {
    # Single-instance: tarefa em 2o plano + monitor do menu rodando juntos =
    # limpeza duplicada e heartbeat sobrescrito. Heartbeat fresco (<3min) de
    # outro PID vivo -> aborta esta instancia. PID reciclado passa se o
    # heartbeat estiver velho; falso positivo exige reuso em <3min (raro).
    if (Test-Path $HeartbeatPath) {
        try {
            $hb  = Get-Content $HeartbeatPath -Raw | ConvertFrom-Json
            $age = ((Get-Date) - [datetime]$hb.UpdatedAt).TotalSeconds
            if ($hb.PID -ne $PID -and $age -lt 180 -and (Get-Process -Id $hb.PID -ErrorAction SilentlyContinue)) {
                Write-Log "Ja existe um monitor ativo (PID $($hb.PID), heartbeat ha $([int]$age)s) - abortando esta instancia." "WARNING"
                return
            }
        } catch {}
    }

    # Formata o limite mostrando % e GB quando ambos estiverem configurados.
    $parts = @()
    if ($null -ne $Config.ThresholdClean   -and "$($Config.ThresholdClean)"   -ne '') { $parts += ("$($Config.ThresholdClean)"   -replace '%','') + '%' }
    if ($null -ne $Config.ThresholdCleanGB -and "$($Config.ThresholdCleanGB)" -ne '') { $parts += ("$($Config.ThresholdCleanGB)" -replace 'gb','') + 'GB' }
    $limiteTxt = if ($parts.Count -eq 0) { '(off)' } else { $parts -join '/' }

    Write-Log "===========================================" "INFO"
    Write-Log "[INICIO] MONITOR DE RAM INICIADO (PID $PID)" "INFO"
    Write-Log "Perfil=$($Config.Profile) | Limite=$limiteTxt de RAM USADA -> acao=$($Config.CleanAction) | motor=$($Config.CleanEngine)" "INFO"
    Write-Log "Intervalo=$($Config.CheckIntervalSeconds)s Cooldown=$($Config.CleanCooldownSeconds)s StepDelay=$($Config.StepDelayMs)ms MinStandby=$($Config.MinStandbyMB)MB" "INFO"
    Write-Log "===========================================" "INFO"

    Clear-RamOldLogs -Days $Config.LogRetentionDays

    # Recarga automatica: perfil aplicado pelo menu passa a valer no proximo
    # ciclo, sem reiniciar o monitor/tarefa.
    $cfgStamp = $null
    try { $cfgStamp = (Get-Item $ConfigPath -ErrorAction Stop).LastWriteTimeUtc } catch {}

    $ErrorCount = 0
    try {
        while ($Config.Enabled) {
            try {
                $t = (Get-Item $ConfigPath -ErrorAction SilentlyContinue).LastWriteTimeUtc
                if ($t -and $t -ne $cfgStamp) {
                    $cfgStamp = $t
                    $script:Config = Read-RamConfig
                    Write-Log "Config alterada em disco - recarregada (perfil='$($Config.Profile)' acao=$($Config.CleanAction) intervalo=$($Config.CheckIntervalSeconds)s)." "INFO"
                }
            } catch {}
            try {
                Test-MemoryAndClean
                $ErrorCount = 0
            }
            catch {
                $ErrorCount++
                Write-Log "Erro no ciclo: $_" "ERROR"
                if ($ErrorCount -gt 5 -and -not $Config.RestartOnError) {
                    Write-Log "Muitos erros consecutivos, encerrando." "ERROR"
                    break
                }
            }
            if (Wait-MonitorInterval -Seconds $Config.CheckIntervalSeconds) {
                Write-Log "Monitor encerrado pelo usuario (tecla Q)." "INFO"
                break
            }
        }
    }
    finally {
        $dur = [int]((Get-Date) - $script:StartTime).TotalMinutes
        Write-Log "[FIM] Monitor encerrado. Sessao: ${dur}min, $($script:CleanCount) limpezas, ~$([math]::Round($script:TotalFreedGB,2))GB liberados." "INFO"
        if (Test-Path $HeartbeatPath) { Remove-Item $HeartbeatPath -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------------------
# Admin (Test-Admin vem do RamCommon)
# ---------------------------------------------------------------------------
function Assert-Admin {
    if (-not (Test-Admin)) {
        Write-Host "[ERRO] Esta operacao requer privilegios de ADMINISTRADOR!" -ForegroundColor Red
        Write-Host "Execute o PowerShell como Administrador." -ForegroundColor Yellow
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Status (nao precisa de admin)
# ---------------------------------------------------------------------------
function Show-Status {
    $Stats     = Get-MemoryStats
    $StandbyMB = Get-StandbyListMB
    Write-Host "`n[STATUS] MEMORIA" -ForegroundColor Cyan
    Write-Host "Usado:      $($Stats.UsedMemoryGB)GB / $($Stats.TotalMemoryGB)GB ($($Stats.PercentUsed)%)"
    Write-Host "Livre:      $($Stats.FreeMemoryGB)GB"
    Write-Host "Standby:    ${StandbyMB}MB (recuperavel via limpeza)"
    $heavy = @(Get-HeavyProcesses)
    if ($heavy.Count -gt 0) {
        $names = ($heavy | Select-Object -First 5 -ExpandProperty ProcessName) -join ", "
        Write-Host "Pesados:    $names" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
switch ($PSCmdlet.ParameterSetName) {
    'Monitor' { Assert-Admin; Start-RAMMonitor; return }
    'Once'    {
        Assert-Admin
        Clear-RamOldLogs -Days $Config.LogRetentionDays
        Restore-CleanState      # cooldown/histerese persistidos entre execucoes
        Test-MemoryAndClean
        Save-CleanState
        return
    }
    'Status'  { Show-Status; return }
    'Clean'   { Assert-Admin; $null = Invoke-RAMClean -Type $Clean; return }
}

# --- Sem params: este script e o motor, nao a interface ---------------------
# A UI (analise, perfis, limpeza manual, dashboard, config, agendamento) vive no
# Menu.ps1. Rodar o engine cru mostra o status e aponta p/ la, em vez de manter
# um segundo menu duplicado.
Show-Status
Write-Host "Este e o MOTOR. Para o menu completo rode Menu.ps1 (ou INICIAR.bat)." -ForegroundColor Cyan
Write-Host "Uso direto: -Monitor | -Once | -Status | -Clean <tipo>" -ForegroundColor DarkGray
