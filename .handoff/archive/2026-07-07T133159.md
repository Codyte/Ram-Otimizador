# Handoff · Ram-Otimizador · 2026-07-06

## Goal
Review + hardening do otimizador de RAM (PowerShell 5.1, Win10/11). Sessão anterior: 11 fixes + feature menu de contexto — TUDO commitado e pushado (commit "Correcoes de review + menu de contexto do Windows").

## State
- Done: 6 bugs corrigidos (log do dia por chamada via Write-RamLog; WorkingSet64 no Dashboard; Teste RAMMap com WaitForExit; single-instance por heartbeat; msgs; status monitor só por heartbeat), 5 melhorias (Test-Admin único no RamCommon; ConvertFrom-RamThresholdToken parser único; cap 2MB cleanup-history.csv; $Root/headers duplicados removidos), feature menu de contexto (Configurar-AutoExecucao opções 4/5, HKCU Directory\Background + DesktopBackground, launcher Limpeza-ContextMenu.ps1 que auto-eleva).
- Verificado: parse 8/8, engine -Status, 11 asserts parser, roundtrip add/remove registro real, Write-RamLog nível+arquivo do dia.
- In progress: nada mid-flight.

## Decisions (and why)
- NÃO spawnar agentes/workflows neste projeto — usuário proibiu (custo). Memória salva em memory/no-subagents.md. Trabalho 100% inline.
- Caveman ultra + ponytail full ativos na sessão.
- Menu de contexto em HKCU (não HKLM) — por usuário, sem admin p/ instalar, universal.
- Launcher .ps1 separado (Limpeza-ContextMenu.ps1) — evita aspas aninhadas no registro.
- Single-instance: heartbeat PID vivo + <3min; PID reciclado em <3min = falso positivo aceito (raro).

## Next steps (ordered)
1. Usuário: reiniciar tarefa 2º plano (Menu → T) — monitor rodando ainda usa código antigo em memória.
2. Usuário: instalar menu de contexto quando quiser (Menu 6 → opção 4).
3. Possível pendência ponytail: nada crítico; docs/README.md (277 linhas) não foi atualizado com a feature nova (só README.txt foi) — atualizar se usuário pedir.

## Key files
- scripts/RamCommon.ps1 — lib compartilhada: Test-Admin, ConvertFrom-RamThresholdToken, Write-RamLog (agora usado pelo engine), Clear-RamOldLogs c/ cap CSV
- scripts/LimparRAM-Inteligente.ps1 — engine; Write-Log delega Write-RamLog; guard single-instance em Start-RAMMonitor
- scripts/Configurar-AutoExecucao.ps1 — $CtxBases/Add-ContextMenu/Remove-ContextMenu (opções 4/5); FullCleanup remove chaves
- scripts/Limpeza-ContextMenu.ps1 — launcher do botão direito (auto-eleva, -Action)
- config/RamCleanerConfig.json — gitignored; atual: ThresholdCleanGB=10, Safe, 10s/20s, DEBUG
- __navi__.md + scripts/__navi__.md — regen via navindex após edits

## Open / blockers
- Nenhum.
