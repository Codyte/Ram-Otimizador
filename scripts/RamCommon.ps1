# ====================== BEGIN NAV INDEX ======================
# NAV INDEX — auto-generated symbol map (refresh via the navindex skill)
#   L46    Test-Admin
#   L55    Set-RAMMapEulaKey
#   L65    Resolve-RAMMap
#   L161   Initialize-NativeClean
#   L175   Invoke-NativeCleanStep
#   L195   Clear-RamOldLogs
#   L215   Get-RamConfigSchema
#   L239   Get-RamConfigComments
#   L260   Convert-RamLegacyConfig
#   L275   Backup-RamInvalidConfig
#   L291   ConvertTo-RamIntSetting
#   L315   ConvertTo-RamBoolSetting
#   L334   ConvertFrom-RamThresholdToken
#   L353   ConvertTo-RamThresholdSetting
#   L376   Normalize-RamConfig
#   L423   Read-RamConfig
#   L453   Write-RamConfig
#   L471   ConvertTo-UsagePercentToken
#   L488   Resolve-UsageThresholdPercent
#   L500   Format-UsageThreshold
#   L520   Get-RamProfiles
#   L581   Apply-RamProfile
#   L601   Get-MemoryStats
#   L616   Get-StandbyListMB
#   L634   Get-HeavyProcesses
#   L647   Get-SystemInfo
#   L673   Get-RecommendedProfile
#   L720   Write-RamLog
# ======================= END NAV INDEX =======================

# Raiz portatil: pasta do projeto = pai da pasta 'scripts' onde este arquivo esta.
# Toda config/logs/heartbeat fica dentro do projeto (.\Ram Otimizador).
$Global:RamRoot       = Split-Path $PSScriptRoot -Parent
$Global:RamConfigPath = Join-Path $Global:RamRoot "config\RamCleanerConfig.json"
$Global:RamLogDir     = Join-Path $Global:RamRoot "logs"
$Global:RamScripts    = Join-Path $Global:RamRoot "scripts"
$Global:RamTaskName   = "LimparRAM-Monitoramento"

foreach ($d in @($Global:RamLogDir, (Split-Path $Global:RamConfigPath))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# Checagem de admin compartilhada (Menu/engine/configurador usam esta copia unica).
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Aceita o EULA do RAMMap numa colmeia de registro (HKCU do usuario ou S-1-5-18
# do SYSTEM). Retorna $true se mudou algo, $false se ja estava aceito. O logging
# fica no chamador porque cada contexto usa canal diferente (Write-Log vs Write-Host).
function Set-RAMMapEulaKey {
    param([Parameter(Mandatory)][string]$RegPath)
    if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
    if ((Get-ItemProperty -Path $RegPath -Name 'EulaAccepted' -ErrorAction SilentlyContinue).EulaAccepted -eq 1) { return $false }
    New-ItemProperty -Path $RegPath -Name 'EulaAccepted' -Value 1 -PropertyType DWord -Force | Out-Null
    return $true
}

# Auto-deteccao do RAMMap. Prioriza a copia local (.\scripts\RAMMap.exe),
# entao locais comuns + PATH como fallback.
function Resolve-RAMMap {
    $candidates = @(
        (Join-Path $PSScriptRoot "RAMMap64.exe"),
        (Join-Path $PSScriptRoot "RAMMap.exe"),
        "C:\Softwares Instaladores\SysInternals\RAMMap64.exe",
        "C:\Softwares Instaladores\SysInternals\RAMMap.exe",
        "C:\Tools\Sysinternals\RAMMap64.exe",
        "C:\Tools\Sysinternals\RAMMap.exe",
        "$env:ProgramData\chocolatey\bin\RAMMap.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command RAMMap64.exe, RAMMap.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

# ---------------------------------------------------------------------------
# Motor NATIVO de limpeza (NtSetSystemInformation) - dispensa o RAMMap
# ---------------------------------------------------------------------------
# Faz as mesmas operacoes que o RAMMap, direto na API do Windows: sem spawnar
# processo externo por passo e sem o hack de EULA da Sysinternals. Exige admin:
# SeProfileSingleProcessPrivilege (listas de memoria) e SeIncreaseQuotaPrivilege
# (working set do sistema / file cache).
$script:RamNativeSource = @'
using System;
using System.Runtime.InteropServices;

public static class RamNative
{
    [DllImport("ntdll.dll")]
    private static extern uint NtSetSystemInformation(int systemInformationClass, ref int systemInformation, int systemInformationLength);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetSystemFileCacheSize(IntPtr minimumFileCacheSize, IntPtr maximumFileCacheSize, int flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string systemName, string name, out long luid);

    // Pack=1: LUID fica no offset 4 (como no layout real da API); sem isso o
    // alinhamento de 8 bytes desloca a struct e AdjustTokenPrivileges falha.
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct TOKEN_PRIVILEGES
    {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr tokenHandle, bool disableAllPrivileges, ref TOKEN_PRIVILEGES newState, int bufferLength, IntPtr previousState, IntPtr returnLength);

    private const int SystemMemoryListInformation = 80;
    private const int SE_PRIVILEGE_ENABLED = 0x2;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x20;
    private const uint TOKEN_QUERY = 0x8;

    public static bool EnablePrivilege(string privilegeName)
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token)) return false;
        try
        {
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Attributes = SE_PRIVILEGE_ENABLED;
            if (!LookupPrivilegeValue(null, privilegeName, out tp.Luid)) return false;
            if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return false;
            return Marshal.GetLastWin32Error() == 0;   // 1300 = ERROR_NOT_ALL_ASSIGNED
        }
        finally { CloseHandle(token); }
    }

    // 2 = EmptyWorkingSets, 3 = FlushModifiedList, 4 = PurgeStandbyList
    public static uint MemoryListCommand(int command)
    {
        int cmd = command;
        return NtSetSystemInformation(SystemMemoryListInformation, ref cmd, 4);
    }

    public static bool EmptySystemWorkingSet()
    {
        return SetSystemFileCacheSize((IntPtr)(-1), (IntPtr)(-1), 0);
    }
}
'@

$Global:RamNativeReady = $null
function Initialize-NativeClean {
    if ($null -ne $Global:RamNativeReady) { return $Global:RamNativeReady }
    try {
        if (-not ('RamNative' -as [type])) {
            Add-Type -TypeDefinition $script:RamNativeSource -ErrorAction Stop
        }
        # Sem SeProfileSingleProcessPrivilege (= sem admin) o motor nao serve.
        $ok = [RamNative]::EnablePrivilege('SeProfileSingleProcessPrivilege')
        [void][RamNative]::EnablePrivilege('SeIncreaseQuotaPrivilege')
        $Global:RamNativeReady = [bool]$ok
    } catch { $Global:RamNativeReady = $false }
    return $Global:RamNativeReady
}

function Invoke-NativeCleanStep {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ModifiedPageList', 'WorkingSets', 'SystemWorkingSets', 'Standby')]
        [string]$Step
    )
    if (-not (Initialize-NativeClean)) { return $false }
    try {
        switch ($Step) {
            'ModifiedPageList'  { return ([RamNative]::MemoryListCommand(3) -eq 0) }
            'WorkingSets'       { return ([RamNative]::MemoryListCommand(2) -eq 0) }
            'SystemWorkingSets' { return [RamNative]::EmptySystemWorkingSet() }
            'Standby'           { return ([RamNative]::MemoryListCommand(4) -eq 0) }
        }
    } catch { return $false }
    return $false
}

# Rotacao de logs: apaga logs diarios mais antigos que N dias e limita o
# historico CSV de limpezas.
function Clear-RamOldLogs {
    param([int]$Days = 30)
    try {
        $cut = (Get-Date).AddDays(-[math]::Max(1, $Days))
        Get-ChildItem $Global:RamLogDir -Filter 'RAMMap_*.log' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cut } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        # ponytail: cap grosseiro por tamanho (cabecalho + ultimas 5000 linhas);
        # rotacao com historico integral so se algum dia precisar auditar tudo.
        $hist = Join-Path $Global:RamLogDir 'cleanup-history.csv'
        if ((Test-Path $hist) -and (Get-Item $hist).Length -gt 2MB) {
            $lines = Get-Content $hist
            Set-Content -Path $hist -Value (@($lines[0]) + ($lines | Select-Object -Last 5000)) -Encoding UTF8
        }
    } catch {}
}

# ---------------------------------------------------------------------------
# Configuracao
# ---------------------------------------------------------------------------
function Get-RamConfigSchema {
    [ordered]@{
        Profile              = "equilibrado"
        # Modelo simples: UM limite dispara UMA acao. Limite hibrido %/GB de RAM USADA.
        ThresholdClean       = 80       # % de RAM USADA que dispara (ou "80%")
        ThresholdCleanGB     = $null    # idem em GB (ou "10.5gb"); combina com % por OR
        CleanAction          = "All"    # All (TUDO) | SafeStrong (Modified+Standby) | Standby
        CleanEngine          = "Auto"   # Auto (nativo se disponivel) | Native | RAMMap
        StepDelayMs          = 400      # delay entre passos de limpeza multi-etapa (ms)
        CheckIntervalSeconds = 30
        CleanCooldownSeconds = 120
        HysteresisPercent    = 3
        MinStandbyMB         = 1024
        Enabled              = $true
        LogLevel             = "INFO"
        LogRetentionDays     = 30
        EnableGameDetection  = $true
        RestartOnError       = $true
        # Bloco de ajuda gravado no proprio JSON (sempre atualizado a partir daqui).
        Comments             = Get-RamConfigComments
    }
}

# Descricao de cada campo (ASCII, sem acento, p/ evitar mojibake no JSON).
function Get-RamConfigComments {
    [ordered]@{
        Profile              = "Perfil ativo. Troque pelo menu (opcao 2); nao edite a mao."
        ThresholdClean       = "Limite de RAM USADA que dispara a limpeza. Numero = % (ex: 80) ou texto (ex: '80%')."
        ThresholdCleanGB     = "Mesmo limite em GB de RAM USADA (ex: 10.5 ou '10.5gb'). null = usar so o %. Se os dois existirem, dispara no que vier primeiro (OU)."
        CleanAction          = "Acao ao atingir o limite: All = TUDO (WorkingSets -> Modified -> Standby); Safe = WorkingSets -> Modified (sem purgar standby; bom pre-desligamento); SafeStrong = Modified+Standby (forte, sem stutter); Standby = so Standby (leve)."
        CleanEngine          = "Motor de limpeza: Auto = API nativa do Windows se disponivel, senao RAMMap; Native = so API nativa; RAMMap = so o exe da Sysinternals."
        StepDelayMs          = "Delay em ms entre os passos de uma limpeza de varias etapas (deixa as paginas migrarem). 0 = sem delay."
        CheckIntervalSeconds = "Segundos entre cada verificacao de memoria."
        CleanCooldownSeconds = "Tempo minimo em segundos entre duas limpezas (anti-thrashing)."
        HysteresisPercent    = "Margem (pontos %) para re-armar apos limpar, evitando repetir no limiar."
        MinStandbyMB         = "So aplica a acao 'Standby' se houver pelo menos esta Standby List (MB)."
        Enabled              = "Ativar/desativar o monitor continuo (true/false)."
        LogLevel             = "DEBUG (tudo), INFO (padrao), WARNING (so alertas), ERROR (so erros)."
        LogRetentionDays     = "Apaga logs diarios (RAMMap_*.log) mais antigos que N dias (1-3650)."
        EnableGameDetection  = "App pesado/jogo aberto rebaixa a acao All para SafeStrong (evita engasgo)."
        RestartOnError       = "Continuar tentando apos varios erros seguidos em vez de encerrar."
    }
}

# Migra o modelo antigo (3 niveis Normal/Urgente/Critico) para o limite unico.
function Convert-RamLegacyConfig {
    param($Loaded)
    $names = $Loaded.PSObject.Properties.Name
    if ($names -notcontains 'ThresholdClean' -and $names -contains 'ThresholdUrgent') {
        $Loaded | Add-Member -NotePropertyName 'ThresholdClean' -NotePropertyValue $Loaded.ThresholdUrgent -Force
        $gb = if ($names -contains 'ThresholdUrgentGB') { $Loaded.ThresholdUrgentGB } else { $null }
        $Loaded | Add-Member -NotePropertyName 'ThresholdCleanGB' -NotePropertyValue $gb -Force
    }
    foreach ($dead in 'ThresholdNormal','ThresholdUrgent','ThresholdCritical',
                      'ThresholdNormalGB','ThresholdUrgentGB','ThresholdCriticalGB') {
        if ($Loaded.PSObject.Properties.Name -contains $dead) { $Loaded.PSObject.Properties.Remove($dead) }
    }
    return $Loaded
}

function Backup-RamInvalidConfig {
    param([Parameter(Mandatory)][string]$Path)

    try {
        if (-not (Test-Path $Path)) { return $null }
        $dir = Split-Path $Path -Parent
        $name = [IO.Path]::GetFileNameWithoutExtension($Path)
        $backup = Join-Path $dir ("{0}.bad-{1}.json" -f $name, (Get-Date -Format "yyyyMMdd-HHmmss"))
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        return $backup
    } catch {
        Write-Warning "Nao foi possivel criar backup da config invalida: $_"
        return $null
    }
}

function ConvertTo-RamIntSetting {
    param(
        [Parameter(Mandatory)][string]$Name,
        $Value,
        [int]$Default,
        [int]$Min,
        [int]$Max
    )

    if ($null -eq $Value -or $Value -is [bool]) {
        Write-Warning "Config '$Name' invalida; usando padrao $Default."
        return $Default
    }
    try { $n = [int]$Value } catch {
        Write-Warning "Config '$Name' invalida ('$Value'); usando padrao $Default."
        return $Default
    }
    if ($n -lt $Min -or $n -gt $Max) {
        Write-Warning "Config '$Name' fora do intervalo ($Min-$Max): $n; usando padrao $Default."
        return $Default
    }
    return $n
}

function ConvertTo-RamBoolSetting {
    param(
        [Parameter(Mandatory)][string]$Name,
        $Value,
        [bool]$Default
    )

    if ($Value -is [bool]) { return $Value }
    $s = "$Value".Trim().ToLowerInvariant()
    if ($s -eq "true") { return $true }
    if ($s -eq "false") { return $false }
    Write-Warning "Config '$Name' invalida ('$Value'); usando padrao $Default."
    return $Default
}

# Parser unico de token de limite ("80", "80%", "10.5gb", "10,5 GB", "512mb")
# -> @{ Num = [double]; Unit = 'percent'|'gb'|'mb' }. $null se vazio/invalido.
# Fonte unica: validacao (ConvertTo-RamThresholdSetting) e conversao
# (ConvertTo-UsagePercentToken) usam este mesmo parse.
function ConvertFrom-RamThresholdToken {
    param($Raw, [ValidateSet('percent','gb')][string]$DefaultUnit = 'percent')
    if ($null -eq $Raw) { return $null }
    if ($Raw -is [ValueType] -and $Raw -isnot [bool]) {
        return @{ Num = [double]$Raw; Unit = $DefaultUnit }
    }
    $s = ([string]$Raw).Trim().ToLowerInvariant() -replace ',', '.'
    if ($s -eq '' -or $s -notmatch '^([0-9]*\.?[0-9]+)\s*(%|gb|g|mb|m)?$') { return $null }
    $unit = switch ($matches[2]) {
        '%'  { 'percent' }
        'gb' { 'gb' }
        'g'  { 'gb' }
        'mb' { 'mb' }
        'm'  { 'mb' }
        default { $DefaultUnit }
    }
    @{ Num = [double]$matches[1]; Unit = $unit }
}

function ConvertTo-RamThresholdSetting {
    param(
        [Parameter(Mandatory)][string]$Name,
        $Value,
        [ValidateSet('percent','gb')][string]$DefaultUnit,
        $Default
    )

    if ($null -eq $Value -or "$Value".Trim() -eq '') { return $null }

    $tok = ConvertFrom-RamThresholdToken -Raw $Value -DefaultUnit $DefaultUnit
    if ($null -eq $tok) {
        Write-Warning "Config '$Name' invalida ('$Value'); usando padrao $Default."
        return $Default
    }
    if ($tok.Num -lt 0 -or ($tok.Unit -eq 'percent' -and $tok.Num -gt 100) -or
        ($tok.Unit -eq 'gb' -and $tok.Num -gt 1048576) -or ($tok.Unit -eq 'mb' -and $tok.Num -gt 1073741824)) {
        Write-Warning "Config '$Name' fora do intervalo: $Value; usando padrao $Default."
        return $Default
    }
    return $Value
}

function Normalize-RamConfig {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Schema
    )

    $allowedActions = @("Standby", "WorkingSets", "SystemWorkingSets", "ModifiedPageList", "Safe", "SafeStrong", "All")
    $action = "$($Config.CleanAction)"
    $matchAction = $allowedActions | Where-Object { $_ -ieq $action } | Select-Object -First 1
    if ($matchAction) { $Config.CleanAction = $matchAction }
    else {
        Write-Warning "Config 'CleanAction' invalida ('$action'); usando padrao $($Schema.CleanAction)."
        $Config.CleanAction = $Schema.CleanAction
    }

    $allowedEngines = @("Auto", "Native", "RAMMap")
    $engine = "$($Config.CleanEngine)"
    $matchEngine = $allowedEngines | Where-Object { $_ -ieq $engine } | Select-Object -First 1
    if ($matchEngine) { $Config.CleanEngine = $matchEngine }
    else {
        Write-Warning "Config 'CleanEngine' invalida ('$engine'); usando padrao $($Schema.CleanEngine)."
        $Config.CleanEngine = $Schema.CleanEngine
    }

    $allowedLevels = @("DEBUG", "INFO", "WARNING", "ERROR")
    $level = "$($Config.LogLevel)".Trim().ToUpperInvariant()
    if ($allowedLevels -contains $level) { $Config.LogLevel = $level }
    else {
        Write-Warning "Config 'LogLevel' invalida ('$($Config.LogLevel)'); usando padrao $($Schema.LogLevel)."
        $Config.LogLevel = $Schema.LogLevel
    }

    $Config.ThresholdClean       = ConvertTo-RamThresholdSetting -Name 'ThresholdClean' -Value $Config.ThresholdClean -DefaultUnit 'percent' -Default $Schema.ThresholdClean
    $Config.ThresholdCleanGB     = ConvertTo-RamThresholdSetting -Name 'ThresholdCleanGB' -Value $Config.ThresholdCleanGB -DefaultUnit 'gb' -Default $Schema.ThresholdCleanGB
    $Config.StepDelayMs          = ConvertTo-RamIntSetting -Name 'StepDelayMs' -Value $Config.StepDelayMs -Default $Schema.StepDelayMs -Min 0 -Max 60000
    $Config.CheckIntervalSeconds = ConvertTo-RamIntSetting -Name 'CheckIntervalSeconds' -Value $Config.CheckIntervalSeconds -Default $Schema.CheckIntervalSeconds -Min 1 -Max 86400
    $Config.CleanCooldownSeconds = ConvertTo-RamIntSetting -Name 'CleanCooldownSeconds' -Value $Config.CleanCooldownSeconds -Default $Schema.CleanCooldownSeconds -Min 0 -Max 86400
    $Config.HysteresisPercent    = ConvertTo-RamIntSetting -Name 'HysteresisPercent' -Value $Config.HysteresisPercent -Default $Schema.HysteresisPercent -Min 0 -Max 50
    $Config.MinStandbyMB         = ConvertTo-RamIntSetting -Name 'MinStandbyMB' -Value $Config.MinStandbyMB -Default $Schema.MinStandbyMB -Min 0 -Max 1048576
    $Config.LogRetentionDays     = ConvertTo-RamIntSetting -Name 'LogRetentionDays' -Value $Config.LogRetentionDays -Default $Schema.LogRetentionDays -Min 1 -Max 3650
    $Config.Enabled              = ConvertTo-RamBoolSetting -Name 'Enabled' -Value $Config.Enabled -Default $Schema.Enabled
    $Config.EnableGameDetection  = ConvertTo-RamBoolSetting -Name 'EnableGameDetection' -Value $Config.EnableGameDetection -Default $Schema.EnableGameDetection
    $Config.RestartOnError       = ConvertTo-RamBoolSetting -Name 'RestartOnError' -Value $Config.RestartOnError -Default $Schema.RestartOnError

    return $Config
}

function Read-RamConfig {
    $schema = Get-RamConfigSchema
    if (Test-Path $Global:RamConfigPath) {
        try {
            $loaded = Convert-RamLegacyConfig (Get-Content $Global:RamConfigPath -Raw | ConvertFrom-Json)
            $existing = $loaded.PSObject.Properties.Name
            foreach ($k in $schema.Keys) {
                if ($existing -notcontains $k) {
                    $loaded | Add-Member -NotePropertyName $k -NotePropertyValue $schema[$k]
                }
            }
            $loaded = Normalize-RamConfig -Config $loaded -Schema $schema
            # Bloco de ajuda: sempre reescrito a partir do schema (documentacao, nao editavel).
            $loaded | Add-Member -NotePropertyName 'Comments' -NotePropertyValue (Get-RamConfigComments) -Force
            return $loaded
        } catch {
            $backup = Backup-RamInvalidConfig -Path $Global:RamConfigPath
            if ($backup) {
                Write-Warning "Config invalido ($_); backup criado em '$backup'. Usando padrao em memoria."
            } else {
                Write-Warning "Config invalido ($_); usando padrao em memoria."
            }
            return [pscustomobject]$schema
        }
    }
    $cfg = [pscustomobject]$schema
    Write-RamConfig $cfg
    return $cfg
}

function Write-RamConfig {
    param([Parameter(Mandatory)]$Config)
    $Config | ConvertTo-Json -Depth 5 | Out-File $Global:RamConfigPath -Encoding UTF8 -Force
}

# ---------------------------------------------------------------------------
# Limites hibridos (% e/ou GB de RAM USADA)
# ---------------------------------------------------------------------------
# O limite tem um campo % (ThresholdClean) e um GB (ThresholdCleanGB) opcional.
# Ambos descrevem RAM USADA. Quando os dois existem, combinam por OR: o limite
# dispara assim que QUALQUER um for atingido (o mais agressivo vence).
#
# Aceita: numero puro (unidade = a do campo), "75%", "10.5gb"/"10,5 GB",
# "512mb". Locale PT-BR (virgula decimal) tolerado. $null/"" = nao definido.

# Converte UM token para "% de RAM usada". DefaultUnit decide a unidade quando
# o valor e um numero cru (campo % => percent; campo *GB => gb). Retorna $null
# se o token estiver vazio/invalido ou exigir total e ele for desconhecido.
function ConvertTo-UsagePercentToken {
    param(
        $Raw,
        [ValidateSet('percent', 'gb')][string]$DefaultUnit = 'percent',
        [double]$TotalGB = 0
    )
    $tok = ConvertFrom-RamThresholdToken -Raw $Raw -DefaultUnit $DefaultUnit
    if ($null -eq $tok) { return $null }
    switch ($tok.Unit) {
        'percent' { return $tok.Num }
        'gb'      { if ($TotalGB -gt 0) { return ($tok.Num / $TotalGB) * 100 } else { return $null } }
        'mb'      { if ($TotalGB -gt 0) { return (($tok.Num / 1024) / $TotalGB) * 100 } else { return $null } }
    }
}

# Resolve um nivel (campo % + campo GB) para o % EFETIVO de RAM usada que o
# dispara. OR => o menor % (mais agressivo) vence. $null se nada definido.
function Resolve-UsageThresholdPercent {
    param($PercentValue, $GBValue, [double]$TotalGB = 0)
    $candidates = @()
    $p = ConvertTo-UsagePercentToken -Raw $PercentValue -DefaultUnit 'percent' -TotalGB $TotalGB
    if ($null -ne $p) { $candidates += $p }
    $g = ConvertTo-UsagePercentToken -Raw $GBValue -DefaultUnit 'gb' -TotalGB $TotalGB
    if ($null -ne $g) { $candidates += $g }
    if ($candidates.Count -eq 0) { return $null }
    return [math]::Round((($candidates | Measure-Object -Minimum).Minimum), 2)
}

# Texto curto para exibir um nivel (ex: "20% ou 10.5GB", "75%", "8GB").
function Format-UsageThreshold {
    param($PercentValue, $GBValue)
    $parts = @()
    if ($null -ne $PercentValue -and "$PercentValue" -ne '') {
        $t = "$PercentValue"
        if ($t -match '^[0-9.]+$') { $t += '%' }
        $parts += $t
    }
    if ($null -ne $GBValue -and "$GBValue" -ne '') {
        $t = "$GBValue"
        if ($t -match '^[0-9.]+$') { $t += 'GB' }
        $parts += $t
    }
    if ($parts.Count -eq 0) { return '-' }
    return ($parts -join ' ou ')
}

# ---------------------------------------------------------------------------
# Perfis pre-prontos para varias situacoes
# ---------------------------------------------------------------------------
function Get-RamProfiles {
    # Cada perfil = UM limite (ThresholdClean, %/GB) + UMA acao (CleanAction):
    #   All        = TUDO (WorkingSets -> Modified -> Standby). Libera mais, mas
    #                Working Sets pode causar engasgo em jogo / latencia em servidor.
    #   Safe       = WorkingSets -> Modified, sem purgar a Standby (pre-desligamento).
    #   SafeStrong = Modified + Standby (sem Working Sets). Forte e sem stutter.
    #   Standby    = so Standby. Mais leve.
    # ThresholdCleanGB opcional ($null = usar so o %; ex: 10.5 ou "10.5gb").
    [ordered]@{
        equilibrado = [ordered]@{
            Description          = "Uso geral de desktop. TUDO ao atingir o limite (com guarda anti-stutter)."
            ThresholdClean = 82; ThresholdCleanGB = $null; CleanAction = "All"
            CheckIntervalSeconds = 30; CleanCooldownSeconds = 120; StepDelayMs = 400
            HysteresisPercent = 3; MinStandbyMB = 1024
            LogLevel = "INFO"; EnableGameDetection = $true; RestartOnError = $true
        }
        games = [ordered]@{
            Description          = "Jogos. SafeStrong (Modified+Standby) p/ liberar RAM sem stutter no jogo."
            ThresholdClean = 80; ThresholdCleanGB = $null; CleanAction = "SafeStrong"
            CheckIntervalSeconds = 15; CleanCooldownSeconds = 60; StepDelayMs = 400
            HysteresisPercent = 4; MinStandbyMB = 512
            LogLevel = "INFO"; EnableGameDetection = $true; RestartOnError = $true
        }
        "servidor-24-7" = [ordered]@{
            Description          = "Servidor 24/7. SafeStrong, limite alto e cooldown longo (sem picos de latencia)."
            ThresholdClean = 90; ThresholdCleanGB = $null; CleanAction = "SafeStrong"
            CheckIntervalSeconds = 60; CleanCooldownSeconds = 300; StepDelayMs = 500
            HysteresisPercent = 2; MinStandbyMB = 2048
            LogLevel = "WARNING"; EnableGameDetection = $false; RestartOnError = $true
        }
        "workstation-criacao" = [ordered]@{
            Description          = "Edicao de video/3D. SafeStrong p/ nao trimar o working set dos editores."
            ThresholdClean = 88; ThresholdCleanGB = $null; CleanAction = "SafeStrong"
            CheckIntervalSeconds = 30; CleanCooldownSeconds = 180; StepDelayMs = 400
            HysteresisPercent = 3; MinStandbyMB = 2048
            LogLevel = "INFO"; EnableGameDetection = $true; RestartOnError = $true
        }
        "low-ram" = [ordered]@{
            Description          = "Maquinas com pouca RAM (<=8GB). TUDO, agressivo p/ manter responsividade."
            ThresholdClean = 72; ThresholdCleanGB = $null; CleanAction = "All"
            CheckIntervalSeconds = 20; CleanCooldownSeconds = 90; StepDelayMs = 300
            HysteresisPercent = 4; MinStandbyMB = 512
            LogLevel = "INFO"; EnableGameDetection = $true; RestartOnError = $true
        }
        "economia-bateria" = [ordered]@{
            Description          = "Notebook na bateria. So Standby, limite alto e cooldown enorme (poupa energia)."
            ThresholdClean = 90; ThresholdCleanGB = $null; CleanAction = "Standby"
            CheckIntervalSeconds = 120; CleanCooldownSeconds = 600; StepDelayMs = 0
            HysteresisPercent = 2; MinStandbyMB = 1536
            LogLevel = "WARNING"; EnableGameDetection = $false; RestartOnError = $true
        }
        "agressivo-maximo" = [ordered]@{
            Description          = "Maxima RAM livre a todo custo. TUDO cedo. Pode reduzir cache de disco."
            ThresholdClean = 65; ThresholdCleanGB = $null; CleanAction = "All"
            CheckIntervalSeconds = 15; CleanCooldownSeconds = 45; StepDelayMs = 300
            HysteresisPercent = 5; MinStandbyMB = 256
            LogLevel = "INFO"; EnableGameDetection = $true; RestartOnError = $true
        }
    }
}

function Apply-RamProfile {
    param([Parameter(Mandatory)][string]$Name)
    $profiles = Get-RamProfiles
    if (-not $profiles.Contains($Name)) { throw "Perfil desconhecido: $Name" }

    $p   = $profiles[$Name]
    $cfg = Read-RamConfig
    $cfg.Profile = $Name
    foreach ($k in $p.Keys) {
        if ($k -eq "Description") { continue }
        if ($cfg.PSObject.Properties.Name -contains $k) { $cfg.$k = $p[$k] }
        else { $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $p[$k] -Force }
    }
    Write-RamConfig $cfg
    return $cfg
}

# ---------------------------------------------------------------------------
# Metricas
# ---------------------------------------------------------------------------
function Get-MemoryStats {
    $OS = Get-CimInstance Win32_OperatingSystem
    # Valores CIM vem em KB. KB / 1MB(=1048576) = GB (sem dividir de novo).
    $Free  = $OS.FreePhysicalMemory / 1MB
    $Total = $OS.TotalVisibleMemorySize / 1MB
    $Used  = $Total - $Free
    @{
        FreeMemoryGB  = [math]::Round($Free, 2)
        TotalMemoryGB = [math]::Round($Total, 2)
        UsedMemoryGB  = [math]::Round($Used, 2)
        PercentUsed   = [math]::Round(($Used / $Total) * 100, 2)
    }
}

# Standby List em MB via classe CIM language-neutral (Get-Counter quebra em PT-BR)
function Get-StandbyListMB {
    try {
        $m = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
        $standby = $m.StandbyCacheCoreBytes + $m.StandbyCacheNormalPriorityBytes + $m.StandbyCacheReserveBytes
        return [math]::Round($standby / 1MB, 0)
    } catch { return -1 }
}

# ---------------------------------------------------------------------------
# Deteccao de processos pesados
# ---------------------------------------------------------------------------
# Sem termos genericos tipo "game": casavam com processos do proprio Windows
# (GameBar, gamingservices) e rebaixavam a limpeza All -> SafeStrong a toa.
$Global:RamGameApps     = @("rust","warzone","battlefield","gtav","valorant","csgo","cs2","fortnite","leagueclient","steam","epicgames")
$Global:RamCreatorApps  = @("premiere","blender","davinci","resolve","photoshop","aftereffects","illustrator","unreal","unity","3dsmax","maya")
# Processos de sistema que nunca devem contar como "app pesado".
$Global:RamHeavyExclude = @("gamebar","gamingservices","svchost","memcompression","dwm","registry")

function Get-HeavyProcesses {
    $known = $Global:RamGameApps + $Global:RamCreatorApps + @("chrome","firefox","msedge","obs","discord")
    Get-Process | Where-Object {
        $proc = $_
        if (($Global:RamHeavyExclude | Where-Object { $proc.ProcessName -match $_ }).Count -gt 0) { return $false }
        ($proc.WorkingSet64 -gt 500MB -and ($known | Where-Object { $proc.ProcessName -match $_ }).Count -gt 0) -or
        ($proc.WorkingSet64 -gt 2GB)
    }
}

# ---------------------------------------------------------------------------
# Analise do sistema
# ---------------------------------------------------------------------------
function Get-SystemInfo {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cs  = Get-CimInstance Win32_ComputerSystem
    $enc = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue

    $totalGB    = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $isServer   = ($os.ProductType -ne 1)               # 1=workstation; 2/3=server
    $portTypes  = @(8,9,10,11,12,14,18,21,30,31,32)     # chassis portateis
    $isPortable = $false
    foreach ($t in @($enc.ChassisTypes)) { if ($portTypes -contains [int]$t) { $isPortable = $true } }
    $hasBattery = [bool]$bat

    [pscustomobject]@{
        OSName      = $os.Caption
        IsServer    = $isServer
        IsPortable  = ($isPortable -or $hasBattery)
        HasBattery  = $hasBattery
        TotalRAMGB  = $totalGB
        CPUCores    = $cs.NumberOfLogicalProcessors
        Manufacturer= $cs.Manufacturer
        Model       = $cs.Model
    }
}

# Recomenda o melhor perfil + lista de razoes
function Get-RecommendedProfile {
    $sys   = Get-SystemInfo
    $heavy = @(Get-HeavyProcesses)
    $names = ($heavy | Select-Object -ExpandProperty ProcessName) -join " "

    $hasGame    = $false; $hasCreator = $false
    foreach ($g in $Global:RamGameApps)    { if ($names -match $g) { $hasGame = $true } }
    foreach ($c in $Global:RamCreatorApps) { if ($names -match $c) { $hasCreator = $true } }

    $reasons = @()
    $profile = "equilibrado"

    if ($sys.IsServer) {
        $profile = "servidor-24-7"; $reasons += "SO de servidor detectado ($($sys.OSName))."
    }
    elseif ($hasCreator) {
        $profile = "workstation-criacao"; $reasons += "App de criacao/edicao em execucao."
    }
    elseif ($hasGame) {
        $profile = "games"; $reasons += "Jogo/launcher de jogo em execucao."
    }
    elseif ($sys.IsPortable) {
        $profile = "economia-bateria"; $reasons += "Maquina portatil/com bateria detectada."
    }
    elseif ($sys.TotalRAMGB -le 8) {
        $profile = "low-ram"; $reasons += "Pouca RAM total ($($sys.TotalRAMGB)GB)."
    }
    else {
        $reasons += "Desktop comum sem cargas especiais; perfil balanceado."
    }

    # Ajuste: pouca RAM em qualquer cenario reforca agressividade
    if ($sys.TotalRAMGB -le 8 -and $profile -eq "equilibrado") { $profile = "low-ram" }

    [pscustomobject]@{
        Profile = $profile
        Reasons = $reasons
        System  = $sys
        Heavy   = $heavy
    }
}

# ---------------------------------------------------------------------------
# Logging compartilhado
# ---------------------------------------------------------------------------
$Global:RamLevelRank = @{ DEBUG = 0; INFO = 1; WARNING = 2; ERROR = 3 }

function Write-RamLog {
    param([string]$Message, [string]$Level = "INFO", [string]$MinLevel = "DEBUG")
    if ($Global:RamLevelRank[$Level] -lt $Global:RamLevelRank[$MinLevel]) { return }
    $ts  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    $path = Join-Path $Global:RamLogDir "RAMMap_$(Get-Date -Format 'yyyy-MM-dd').log"
    switch ($Level) {
        "INFO"    { Write-Host $log -ForegroundColor Green }
        "WARNING" { Write-Host $log -ForegroundColor Yellow }
        "ERROR"   { Write-Host $log -ForegroundColor Red }
        default   { Write-Host $log -ForegroundColor Gray }
    }
    Add-Content -Path $path -Value $log -Force
}
