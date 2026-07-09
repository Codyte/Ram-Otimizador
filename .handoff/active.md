# Handoff · Ram-Otimizador · 2026-07-09

## Goal
UI gráfica do otimizador de RAM — CRIADA, TESTADA E PUSHADA (3 commits hoje). Projeto público, PowerShell 5.1.

## State
- HEAD: d8e654d (tudo commitado+pushado; working tree limpa exceto config pessoal)
- Done hoje:
  1. UI completa: scripts/UI-Server.ps1 (HttpListener localhost+token, 11 rotas JSON, Edge --app, auto-shutdown 90s s/ request) + ui/index.html (single-file vanilla offline, dark, gauge células "pente de RAM") + scripts/Iniciar-UI.vbs
  2. Integrações: Menu.ps1 opção U; Add-ContextMenu ganhou chave '00' "Abrir Painel (UI)" acima do 01 (entradas agora carregam comando completo)
  3. Safe = CleanAction padrão (schema+GUIA+docs) — decisão do usuário validada por bench real (Safe −1,6GB uso; SafeStrong ~0). Engine: guarda anti-stutter agora rebaixa Safe→SafeStrong também (antes só All) — LimparRAM-Inteligente.ps1 ~L369
  4. UI compacta (essencial cabe em 760×560): Perfis/Config/Histórico/Logs em <details> colapsáveis; escala reduzida
  5. Legendas explícitas: cada botão com descrição visível; config field.title = Comments do schema (fonte única); hints nos summaries/pills
- Bugs corrigidos em teste real: Get-Content strings c/ PSPath viravam objetos no JSON (fix: "$_"); auto-shutdown derrubava server durante limpeza longa (fix: LastPoll em qualquer request autenticado)
- Verificado: todas as rotas API exercitadas (403 s/ token, config roundtrip, clean real −9,5GB standby, recommend, history 69 rows); 2 screenshots Playwright (JS errors: none); test-RamConfig verde

## Decisions (and why)
- NÃO spawnar agentes/workflows (memória no-subagents.md); trabalho inline; caveman ultra + ponytail full
- UI = HTML + HttpListener + Edge --app (aprovado pelo usuário; zero deps, IA edita fácil) — NÃO WPF
- Token de sessão obrigatório em toda rota (trust boundary; não simplificar)
- Safe padrão por experiência do usuário + bench; labels antigas "recomendado" eram sobras sem teste
- Config pessoal (config/RamCleanerConfig.json) é TRACKED no git; usuário mexeu nela pela UI (CleanEngine=RAMMap) — commitada assim; avisado que Auto é melhor
- Skills UI instaladas em ~/.agents/skills: frontend-design, theme-factory, web-artifacts-builder, webapp-testing

## Next steps (ordered)
1. Usuário: reabrir painel p/ ver versão compacta+legendas (janela aberta serve HTML antigo)
2. Usuário: reinstalar menu de contexto (Menu 6→4) p/ ganhar entrada "Abrir Painel (UI)"
3. Possíveis próximos: screenshot real no docs/README.md (placeholder não criado); i18n/tema claro se pedirem; CleanEngine dele está RAMMap (sugerido voltar Auto)

## Key files
- scripts/UI-Server.ps1 — backend; contrato da API no comentário topo; -NoBrowser/-UrlFile p/ teste
- ui/index.html — front; seções [CSS]/[HTML]/[JS] comentadas; api() c/ token; poll 2s
- scripts/LimparRAM-Inteligente.ps1:369 — guarda de jogo (Safe|All→SafeStrong)
- scripts/RamCommon.ps1:221 — schema default CleanAction=Safe; L239 Comments (UI usa)
- scripts/Configurar-AutoExecucao.ps1:153 — Add-ContextMenu c/ item 00
- Teste manual do server: Start-Process elevado c/ -NoBrowser -UrlFile → IRM com header X-Token

## Open / blockers
- Nenhum. Tudo pushado (origin/master d8e654d).
