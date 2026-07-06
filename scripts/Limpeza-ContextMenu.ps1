# Lancador do menu de contexto (botao direito -> Ram-Otimizador > acao).
# Existe para o comando no registro ficar simples (so -File + -Action, sem
# aspas aninhadas). Auto-eleva (limpeza exige admin) e segura a janela aberta
# para o usuario ler o resultado.
param(
    [Parameter(Mandatory)]
    [ValidateSet("WorkingSets", "ModifiedPageList", "Standby", "All", "Safe")]
    [string]$Action
)

. (Join-Path $PSScriptRoot "RamCommon.ps1")

if (-not (Test-Admin)) {
    # UAC recusado -> Start-Process lanca; sai silencioso (nada a fazer sem admin).
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList `
            "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
    } catch {}
    exit
}

& (Join-Path $PSScriptRoot "LimparRAM-Inteligente.ps1") -Clean $Action
Read-Host "`nEnter para fechar"
