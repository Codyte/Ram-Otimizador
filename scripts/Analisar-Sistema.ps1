# Analisador inteligente do sistema -> recomenda perfil de limpeza de RAM.
# Standalone (dot-source RamCommon). Tambem acessivel pelo Menu.ps1.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "RamCommon.ps1")

$rec = Get-RecommendedProfile
$s   = $rec.System
$mem = Get-MemoryStats

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        ANALISE INTELIGENTE DO SISTEMA" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host (" Maquina   : {0} {1}" -f $s.Manufacturer, $s.Model) -ForegroundColor Gray
Write-Host (" SO        : {0}" -f $s.OSName) -ForegroundColor Gray
Write-Host (" RAM total : {0} GB   Nucleos: {1}" -f $s.TotalRAMGB, $s.CPUCores) -ForegroundColor Gray
Write-Host (" RAM agora : {0}GB / {1}GB ({2}%)  Standby: {3}MB" -f `
    $mem.UsedMemoryGB, $mem.TotalMemoryGB, $mem.PercentUsed, (Get-StandbyListMB)) -ForegroundColor Gray
Write-Host (" Tipo      : {0}{1}{2}" -f `
    $(if ($s.IsServer) {"Servidor "} else {"Workstation "}),
    $(if ($s.IsPortable) {"Portatil "} else {"Desktop "}),
    $(if ($s.HasBattery) {"(com bateria)"} else {""})) -ForegroundColor Gray
if ($rec.Heavy.Count -gt 0) {
    $hn = ($rec.Heavy | Select-Object -First 8 -ExpandProperty ProcessName) -join ", "
    Write-Host (" Pesados   : {0}" -f $hn) -ForegroundColor Yellow
}
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host (" PERFIL RECOMENDADO: {0}" -f $rec.Profile.ToUpper()) -ForegroundColor Green
foreach ($r in $rec.Reasons) { Write-Host ("   - {0}" -f $r) -ForegroundColor Gray }
Write-Host ("   {0}" -f (Get-RamProfiles)[$rec.Profile].Description) -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor Cyan

$cfg = Read-RamConfig
if ($cfg.Profile -ne $rec.Profile) {
    $ans = Read-Host "`nPerfil ativo e '$($cfg.Profile)'. Aplicar o recomendado '$($rec.Profile)'? (S/N)"
    if ($ans -match '^[sS]') {
        Apply-RamProfile -Name $rec.Profile | Out-Null
        Write-Host "[OK] Perfil aplicado." -ForegroundColor Green
    }
} else {
    Write-Host "`n[OK] O perfil ativo ja e o recomendado." -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.') { Read-Host "`nEnter para fechar" }
