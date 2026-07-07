# Teste de regressao do parser/limites de config (RamCommon). Sem Pester, sem
# framework: asserts + exit code (0 = tudo passou, 1 = falhou). Nao precisa admin
# e NAO toca a config real (so chama funcoes puras + Get-RamProfiles read-only).
# Roda: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-RamConfig.ps1
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "RamCommon.ps1") *> $null

$script:fails = 0
function Check($label, $cond) {
    if ($cond) { Write-Host "  ok   $label" -ForegroundColor Green }
    else       { Write-Host "  FAIL $label" -ForegroundColor Red; $script:fails++ }
}

Write-Host "ConvertFrom-RamThresholdToken:" -ForegroundColor Cyan
Check "null -> null"                   ($null -eq (ConvertFrom-RamThresholdToken $null))
$t = ConvertFrom-RamThresholdToken 85
Check "85 -> 85 percent"               ($t.Num -eq 85 -and $t.Unit -eq 'percent')
$t = ConvertFrom-RamThresholdToken "85%"
Check "'85%' -> 85 percent"            ($t.Num -eq 85 -and $t.Unit -eq 'percent')
$t = ConvertFrom-RamThresholdToken "10gb"
Check "'10gb' -> 10 gb"                ($t.Num -eq 10 -and $t.Unit -eq 'gb')
$t = ConvertFrom-RamThresholdToken "10,5 GB"
Check "'10,5 GB' -> 10.5 gb (locale)"  ($t.Num -eq 10.5 -and $t.Unit -eq 'gb')
$t = ConvertFrom-RamThresholdToken "512mb"
Check "'512mb' -> 512 mb"              ($t.Num -eq 512 -and $t.Unit -eq 'mb')
$t = ConvertFrom-RamThresholdToken 10 'gb'
Check "10 (DefaultUnit gb) -> 10 gb"   ($t.Num -eq 10 -and $t.Unit -eq 'gb')
Check "'abc' -> null"                  ($null -eq (ConvertFrom-RamThresholdToken "abc"))
Check "'' -> null"                     ($null -eq (ConvertFrom-RamThresholdToken ""))

Write-Host "Resolve-UsageThresholdPercent (OR = mais agressivo vence):" -ForegroundColor Cyan
Check "80% / - @16 -> 80"              ((Resolve-UsageThresholdPercent "80%" $null 16) -eq 80)
Check "- / 8gb @16 -> 50"              ((Resolve-UsageThresholdPercent $null "8gb" 16) -eq 50)
Check "80% / 8gb @16 -> 50 (min)"      ((Resolve-UsageThresholdPercent "80%" "8gb" 16) -eq 50)
Check "- / - -> null"                  ($null -eq (Resolve-UsageThresholdPercent $null $null 16))
Check "- / 8gb @0 -> null (sem total)" ($null -eq (Resolve-UsageThresholdPercent $null "8gb" 0))

Write-Host "ConvertTo-RamThresholdSetting (valida/repara p/ default):" -ForegroundColor Cyan
Check "valido '85%' -> '85%'"          ((ConvertTo-RamThresholdSetting -Name t -Value "85%"  -DefaultUnit percent -Default "90%") -eq "85%")
Check "'abc' (invalido) -> default"    ((ConvertTo-RamThresholdSetting -Name t -Value "abc"  -DefaultUnit percent -Default "90%") -eq "90%")
Check "'150%' (fora) -> default"       ((ConvertTo-RamThresholdSetting -Name t -Value "150%" -DefaultUnit percent -Default "90%") -eq "90%")
Check "'' -> null"                     ($null -eq (ConvertTo-RamThresholdSetting -Name t -Value "" -DefaultUnit percent -Default "90%"))

Write-Host "Get-RamProfiles (integridade dos perfis pre-prontos):" -ForegroundColor Cyan
$profiles = Get-RamProfiles
$allowed  = @("Standby","WorkingSets","SystemWorkingSets","ModifiedPageList","Safe","SafeStrong","All")
Check "tem perfis"                     ($profiles.Count -gt 0)
$badAction = $profiles.Values | Where-Object { $allowed -notcontains "$($_.CleanAction)" }
Check "toda CleanAction valida"        (-not $badAction)
$badThr = foreach ($p in $profiles.Values) {
    $r = Resolve-UsageThresholdPercent $p.ThresholdClean $p.ThresholdCleanGB 16
    if ($null -ne $r -and ($r -lt 0 -or $r -gt 100)) { $p }
}
Check "todo limite resolve 0-100/null" (-not $badThr)

Write-Host ""
if ($script:fails -eq 0) { Write-Host "TODOS OS TESTES PASSARAM" -ForegroundColor Green; exit 0 }
else { Write-Host "$($script:fails) TESTE(S) FALHARAM" -ForegroundColor Red; exit 1 }
