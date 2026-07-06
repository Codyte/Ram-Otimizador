# Lancador do menu de contexto (botao direito -> Ram-Otimizador > acao).
# Existe para o comando no registro ficar simples. Auto-eleva e roda em segundo plano.
param(
    [Parameter(Mandatory)]
    [ValidateSet("WorkingSets", "ModifiedPageList", "Standby", "All", "Safe")]
    [string]$Action
)

. (Join-Path $PSScriptRoot "RamCommon.ps1")

if (-not (Test-Admin)) {
    # UAC recusado -> Start-Process lanca; sai silencioso.
    try {
        # O parâmetro -WindowStyle Hidden oculta a janela principal e a janela do PowerShell interno
        Start-Process powershell.exe -WindowStyle Hidden -Verb RunAs -ArgumentList `
            "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
    } catch {}
    exit
}

& (Join-Path $PSScriptRoot "LimparRAM-Inteligente.ps1") -Clean $Action

# A linha abaixo deve ser removida ou comentada. 
# Sem isso, o processo oculto ficaria travado aguardando o usuário.
# Read-Host "`nEnter para fechar"