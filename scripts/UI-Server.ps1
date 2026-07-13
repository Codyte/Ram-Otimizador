# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L77    Send-Json
#   L86    Send-Text
#   L95    Read-JsonBody
#   L106   Get-UiStatus
#   L141   Invoke-UiClean
#   L165   Set-UiTask
#   L230   Invoke-UiRoute
# ======================= END NAV INDEX =======================

#
# Painel grafico do Ram-Otimizador: servidor HTTP local (HttpListener) que serve
# ui/index.html e expoe a API JSON abaixo. Aberto no Edge modo --app (janela sem
# barra = parece app nativo); fallback: browser padrao.
#
# API (todas exigem o token de sessao: query ?t=TOKEN ou header X-Token):
#   GET  /                  -> ui/index.html
#   GET  /api/status        -> RAM, standby, heartbeat do monitor, tarefa, perfil, top-5 processos
#   GET  /api/config        -> config atual (Read-RamConfig)
#   POST /api/config        -> merge campos -> Normalize-RamConfig -> Write-RamConfig
#   GET  /api/profiles      -> perfis (Get-RamProfiles) + ativo
#   GET  /api/recommend     -> Get-RecommendedProfile (sob demanda; ~1s de CIM)
#   POST /api/profile       -> {name} -> Apply-RamProfile
#   POST /api/clean         -> {action} -> engine -Clean (bloqueia ate terminar; retorna GB liberado)
#   POST /api/task          -> {op: start|stop|create-monitor|create-periodic|status|
#                                    ctx-add|ctx-remove|remove|cleanup-all, minutes}
#   GET  /api/logs          -> ultimas 50 linhas do log de hoje
#   GET  /api/history       -> linhas do cleanup-history.csv dos ultimos 7 dias
#
# Encerramento: sem GET /api/status por 90s (browser fechado) -> sai sozinho.

param(
    [switch]$NoBrowser,  # p/ teste: sobe o server e imprime a URL, sem abrir janela
    [string]$UrlFile     # p/ teste: grava a URL (com token) neste arquivo
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot "RamCommon.ps1")

# ---------------------------------------------------------------------------
# Auto-elevacao (mesmo padrao do Limpeza-ContextMenu.ps1): limpeza e tarefa
# agendada exigem admin; HttpListener em localhost tambem dispensa URLACL
# quando elevado. UAC recusado -> sai silencioso.
# ---------------------------------------------------------------------------
if (-not (Test-Admin)) {
    try {
        $fwd = if ($NoBrowser) { " -NoBrowser" } else { "" }
        if ($UrlFile) { $fwd += " -UrlFile `"$UrlFile`"" }
        Start-Process powershell.exe -WindowStyle Hidden -Verb RunAs -ArgumentList `
            "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"$fwd"
    } catch {}
    exit
}

$Engine   = Join-Path $PSScriptRoot "LimparRAM-Inteligente.ps1"
$HtmlPath = Join-Path $Global:RamRoot "ui\index.html"
$HbPath   = Join-Path $Global:RamLogDir "monitor-status.json"

# Funcoes do configurador (Add/Remove-ContextMenu, Remove-AutoExec, Invoke-FullCleanup);
# -Lib pula o menu interativo e os prompts.
. (Join-Path $PSScriptRoot "Configurar-AutoExecucao.ps1") -Lib

# ---------------------------------------------------------------------------
# Porta livre (bind 0 e pergunta ao SO) + token de sessao: cada request precisa
# do token (query ?t= ou header X-Token). Trust boundary real: sem ele qualquer
# processo local nao-admin poderia limpar RAM/alterar config via localhost.
# ---------------------------------------------------------------------------
$tcp = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$tcp.Start(); $Port = $tcp.LocalEndpoint.Port; $tcp.Stop()
$Token  = [guid]::NewGuid().ToString('N')
$Prefix = "http://localhost:$Port/"

# ---------------------------------------------------------------------------
# Helpers HTTP
# ---------------------------------------------------------------------------
function Send-Json {
    param($Ctx, $Obj, [int]$Code = 200)
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $Obj -Depth 6))
    $Ctx.Response.StatusCode  = $Code
    $Ctx.Response.ContentType = 'application/json; charset=utf-8'
    $Ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Ctx.Response.Close()
}

function Send-Text {
    param($Ctx, [string]$Text, [string]$Mime = 'text/html; charset=utf-8', [int]$Code = 200)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $Ctx.Response.StatusCode  = $Code
    $Ctx.Response.ContentType = $Mime
    $Ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Ctx.Response.Close()
}

function Read-JsonBody {
    param($Ctx)
    $reader = New-Object IO.StreamReader($Ctx.Request.InputStream, [Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd(); $reader.Close()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# Coleta de status (espelha o Dashboard-RAM: heartbeat + staleness, tarefa, top-5)
# ---------------------------------------------------------------------------
function Get-UiStatus {
    $mem = Get-MemoryStats
    $cfg = Read-RamConfig

    $hb = $null; $hbStale = $false
    if (Test-Path $HbPath) {
        try {
            $hb = Get-Content $HbPath -Raw | ConvertFrom-Json
            $hbAge   = ((Get-Date) - [datetime]$hb.UpdatedAt).TotalSeconds
            $hbAlive = [bool](Get-Process -Id $hb.PID -ErrorAction SilentlyContinue)
            $hbStale = ($hbAge -gt 180) -or (-not $hbAlive)
        } catch { $hbStale = $true }
    }

    $task = Get-ScheduledTask -TaskName $Global:RamTaskName -ErrorAction SilentlyContinue
    $taskState = if ($task) { "$($task.State)" } else { $null }

    $top = Get-Process | Where-Object { $_.WorkingSet64 -gt 0 } |
        Sort-Object WorkingSet64 -Descending | Select-Object -First 5 |
        ForEach-Object { @{ name = $_.ProcessName; mb = [math]::Round($_.WorkingSet64 / 1MB, 0) } }

    @{
        mem       = $mem
        standbyMB = Get-StandbyListMB
        profile   = $cfg.Profile
        threshold = Format-UsageThreshold $cfg.ThresholdClean $cfg.ThresholdCleanGB
        monitor   = @{ running = [bool]($hb -and -not $hbStale); stale = $hbStale; hb = $hb }
        taskState = $taskState
        top       = @($top)
    }
}

# ---------------------------------------------------------------------------
# Limpeza manual: delega ao engine (mesma chamada do Menu.ps1) e mede o ganho.
# ---------------------------------------------------------------------------
function Invoke-UiClean {
    param([string]$Action)
    $allowed = @("Standby", "WorkingSets", "SystemWorkingSets", "ModifiedPageList", "Safe", "SafeStrong", "All")
    $match = $allowed | Where-Object { $_ -ieq $Action } | Select-Object -First 1
    if (-not $match) { throw "Acao invalida: $Action" }

    $before = Get-MemoryStats
    $sbBefore = Get-StandbyListMB
    & $Engine -Clean $match | Out-Null
    $after = Get-MemoryStats
    @{
        ok        = $true
        action    = $match
        freedGB   = [math]::Round([math]::Max(0, $before.UsedMemoryGB - $after.UsedMemoryGB), 2)
        standbyFreedMB = if ($sbBefore -ge 0) { [math]::Max(0, $sbBefore - (Get-StandbyListMB)) } else { $null }
        mem       = $after
    }
}

# ---------------------------------------------------------------------------
# Tarefa em 2o plano. create-* replica o registro do Configurar-AutoExecucao
# (New-MonitorTask/New-PeriodicTask) sem os prompts interativos — aquele script
# roda um menu proprio ao carregar, nao da p/ dot-source.
# ---------------------------------------------------------------------------
function Set-UiTask {
    param([string]$Op, [int]$Minutes = 5)
    $name = $Global:RamTaskName
    switch ($Op) {
        'start' { Start-ScheduledTask -TaskName $name -ErrorAction Stop }
        'stop'  { Stop-ScheduledTask  -TaskName $name -ErrorAction Stop }
        'create-monitor' {
            Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue |
                Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
            try { Set-RAMMapEulaKey 'Registry::HKEY_USERS\S-1-5-18\Software\Sysinternals\RAMMap' | Out-Null } catch {}
            $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            $action = New-ScheduledTaskAction -Execute $ps `
                -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Engine`" -Monitor"
            $settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden `
                -MultipleInstances IgnoreNew `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit ([TimeSpan]::Zero)
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $name -Action $action `
                -Trigger @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn)) `
                -Settings $settings -Principal $principal `
                -Description "Limpeza inteligente de RAM (RAMMap) (monitor continuo)" -Force -ErrorAction Stop | Out-Null
            Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        }
        'create-periodic' {
            if ($Minutes -lt 1) { $Minutes = 5 }
            Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue |
                Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
            try { Set-RAMMapEulaKey 'Registry::HKEY_USERS\S-1-5-18\Software\Sysinternals\RAMMap' | Out-Null } catch {}
            $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            $action = New-ScheduledTaskAction -Execute $ps `
                -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Engine`" -Once"
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
            $settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden `
                -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $name -Action $action `
                -Trigger @($trigger, (New-ScheduledTaskTrigger -AtStartup)) `
                -Settings $settings -Principal $principal `
                -Description "Limpeza inteligente de RAM (RAMMap) (periodico ${Minutes}min)" -Force -ErrorAction Stop | Out-Null
        }
        'status'      { }                              # so leitura; detalhes montados abaixo
        'ctx-add'     { Add-ContextMenu }
        'ctx-remove'  { Remove-ContextMenu }
        'remove'      { Remove-AutoExec }
        'cleanup-all' { Invoke-FullCleanup -Force }
        default { throw "Operacao invalida: $Op" }
    }
    $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    $res = @{ ok = $true; taskState = $(if ($t) { "$($t.State)" } else { $null }) }
    if ($Op -eq 'status' -and $t) {
        $i = $t | Get-ScheduledTaskInfo
        $res.description = $t.Description
        $res.lastRun     = "$($i.LastRunTime)"; $res.lastResult = $i.LastTaskResult
        $res.nextRun     = "$($i.NextRunTime)"
    }
    if ($Op -like 'ctx-*') { $res.ctxInstalled = [bool]($CtxBases | Where-Object { Test-Path $_ }) }
    $res
}

# ---------------------------------------------------------------------------
# Roteador
# ---------------------------------------------------------------------------
function Invoke-UiRoute {
    param($Ctx)
    $req  = $Ctx.Request
    $path = $req.Url.AbsolutePath
    $verb = $req.HttpMethod

    # Autenticacao: token na query (?t=) ou header X-Token. Sem match -> 403.
    $t = $req.QueryString['t']; if (-not $t) { $t = $req.Headers['X-Token'] }
    if ($t -ne $Token) { Send-Json $Ctx @{ error = 'forbidden' } 403; return }
    $script:LastPoll = Get-Date   # qualquer request valido = janela viva (nao so /api/status)

    switch ("$verb $path") {
        'GET /' {
            if (-not (Test-Path $HtmlPath)) { Send-Text $Ctx "ui/index.html nao encontrado" 'text/plain; charset=utf-8' 500; return }
            Send-Text $Ctx (Get-Content $HtmlPath -Raw -Encoding UTF8)
        }
        'GET /api/status' {
            Send-Json $Ctx (Get-UiStatus)
        }
        'GET /api/config' {
            Send-Json $Ctx (Read-RamConfig)
        }
        'POST /api/config' {
            $body = Read-JsonBody $Ctx
            if (-not $body) { Send-Json $Ctx @{ error = 'body vazio' } 400; return }
            $cfg = Read-RamConfig
            # Merge so de campos conhecidos do schema (nunca Comments/Profile via config)
            $editable = @((Get-RamConfigSchema).Keys) | Where-Object { $_ -notin @('Comments', 'Profile') }
            $changed = $false
            foreach ($p in $body.PSObject.Properties) {
                if ($editable -icontains $p.Name -and "$($cfg.($p.Name))" -ne "$($p.Value)") {
                    $cfg.($p.Name) = $p.Value
                    $changed = $true
                }
            }
            # Valores editados a mao nao correspondem mais a nenhum preset.
            if ($changed) { $cfg.Profile = 'personalizado' }
            $cfg = Normalize-RamConfig -Config $cfg -Schema (Get-RamConfigSchema)
            Write-RamConfig $cfg
            Send-Json $Ctx (Read-RamConfig)
        }
        'GET /api/profiles' {
            $profiles = Get-RamProfiles
            $cfg = Read-RamConfig
            $list = foreach ($k in $profiles.Keys) {
                $p = $profiles[$k]
                @{
                    name        = $k
                    description = $p.Description
                    threshold   = Format-UsageThreshold $p.ThresholdClean $p.ThresholdCleanGB
                    action      = $p.CleanAction
                    interval    = $p.CheckIntervalSeconds
                    cooldown    = $p.CleanCooldownSeconds
                    active      = ($k -eq $cfg.Profile)
                }
            }
            Send-Json $Ctx @{ profiles = @($list); active = $cfg.Profile }
        }
        'GET /api/recommend' {
            $rec = Get-RecommendedProfile
            Send-Json $Ctx @{
                profile = $rec.Profile
                reasons = @($rec.Reasons)
                system  = @{
                    os = $rec.System.OSName; ramGB = $rec.System.TotalRAMGB
                    cores = $rec.System.CPUCores; portable = $rec.System.IsPortable
                    server = $rec.System.IsServer; model = "$($rec.System.Manufacturer) $($rec.System.Model)"
                }
                heavy   = @($rec.Heavy | Select-Object -First 6 -ExpandProperty ProcessName)
            }
        }
        'POST /api/profile' {
            $body = Read-JsonBody $Ctx
            $cfg = Apply-RamProfile -Name "$($body.name)"
            Send-Json $Ctx @{ ok = $true; active = $cfg.Profile }
        }
        'POST /api/clean' {
            $body = Read-JsonBody $Ctx
            Send-Json $Ctx (Invoke-UiClean -Action "$($body.action)")
        }
        'POST /api/task' {
            $body = Read-JsonBody $Ctx
            $min = 5; if ($body.minutes) { $min = [int]$body.minutes }
            Send-Json $Ctx (Set-UiTask -Op "$($body.op)" -Minutes $min)
        }
        'GET /api/logs' {
            $log = Join-Path $Global:RamLogDir "RAMMap_$(Get-Date -Format 'yyyy-MM-dd').log"
            # [string] puro: Get-Content decora as strings com PSPath/PSParentPath
            # e o ConvertTo-Json serializa isso como objetos, nao strings.
            $lines = if (Test-Path $log) { @(Get-Content $log -Tail 50 | ForEach-Object { "$_" }) } else { @() }
            Send-Json $Ctx @{ lines = $lines }
        }
        'GET /api/history' {
            $csv = Join-Path $Global:RamLogDir "cleanup-history.csv"
            $rows = @()
            if (Test-Path $csv) {
                $inv = [Globalization.CultureInfo]::InvariantCulture
                $limit = (Get-Date).AddDays(-7)
                $rows = @(Import-Csv $csv | Where-Object {
                    try { [datetime]::ParseExact($_.Timestamp, 's', $inv) -ge $limit } catch { $false }
                } | ForEach-Object {
                    @{
                        ts     = $_.Timestamp
                        action = $_.Action
                        # PT-BR grava virgula decimal; front espera ponto
                        freedGB = [double](("$($_.FreedGB)" -replace ',', '.'))
                        beforePercent = [double](("$($_.BeforePercent)" -replace ',', '.'))
                    }
                })
            }
            Send-Json $Ctx @{ rows = $rows }
        }
        default { Send-Json $Ctx @{ error = 'rota desconhecida' } 404 }
    }
}

# ---------------------------------------------------------------------------
# Loop principal
# ---------------------------------------------------------------------------
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add($Prefix)
$listener.Start()
Write-RamLog "UI iniciada em $Prefix (PID $PID)" "INFO"

$url = "$Prefix`?t=$Token"
if (-not $NoBrowser) {
    # Edge modo --app = janela dedicada sem barra de navegacao (parece nativo).
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
              "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) { Start-Process $edge "--app=$url" }
    else       { Start-Process $url }   # browser padrao (com barra, mas funciona)
} else {
    Write-Host "UI de teste: $url"
}
if ($UrlFile) { Set-Content -Path $UrlFile -Value $url -Force }

# ponytail: single-thread sincrono, 1 usuario local. Auto-shutdown: o front
# faz polling de /api/status a cada 2s; 90s sem poll = janela fechada -> sai.
$script:LastPoll = Get-Date
try {
    while ($true) {
        $task = $listener.GetContextAsync()
        while (-not $task.Wait(1000)) {
            if (((Get-Date) - $script:LastPoll).TotalSeconds -gt 90) {
                Write-RamLog "UI encerrada por inatividade (janela fechada)." "INFO"
                return
            }
        }
        $ctx = $task.Result
        try { Invoke-UiRoute $ctx }
        catch {
            try { Send-Json $ctx @{ error = "$($_.Exception.Message)" } 500 } catch {}
        }
    }
} finally {
    $listener.Stop(); $listener.Close()
}
