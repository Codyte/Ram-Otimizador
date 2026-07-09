================================================================================
  LIMPADOR INTELIGENTE DE RAM
================================================================================

COMO USAR
--------------------------------------------------------------------------------
  Duplo clique em  INICIAR.bat  ->  abre o PAINEL GRAFICO (UI), com limpeza,
  tarefa em 2o plano, perfis, configuracoes, logs e historico (auto-eleva, UAC).

  Prefere o menu classico no console?   INICIAR.bat cmd

  No menu (INICIAR.bat cmd):
    1  Analisar sistema e recomendar perfil
    2  Escolher perfil pre-pronto (games, servidor 24/7, ...)
    3  Iniciar MONITOR continuo (primeiro plano)
    4  Limpeza manual rapida
    5  Dashboard ao vivo
    6  Configurar auto-execucao / agendamento / menu de contexto (2o plano)
    7  Testar sistema (RAMMap, permissoes, arquivos)
    8  Ver logs de hoje
    9  Editar configuracao (JSON)
    U  Abrir painel grafico (UI no navegador, modo app)
    T  Iniciar/Parar a tarefa em 2o plano
    0  Sair

  No monitor em primeiro plano (opcao 3), pressione Q para parar e voltar.
  Perfis aplicados pelo menu valem sozinhos no proximo ciclo do monitor.

  PAINEL GRAFICO (opcao U): interface visual completa no navegador (Edge modo
  app = janela propria, sem barra). RAM ao vivo, limpezas, perfis, configuracao,
  tarefa 2o plano, logs e resumo. Servidor local (so localhost, com token de
  sessao); fecha sozinho ~90s depois de fechar a janela. Requer qualquer
  navegador moderno (Edge ja vem no Windows 10/11).

  MENU DE CONTEXTO (opcional): menu 6 -> opcao 4 adiciona "Ram-Otimizador"
  ao botao direito (fundo da area de trabalho/pasta) com "Abrir Painel (UI)"
  no topo + as limpezas 1-5; opcao 5 remove. Win11: fica em "Mostrar mais
  opcoes". Auto-eleva ao clicar.

COMO FUNCIONA (resumo)
--------------------------------------------------------------------------------
  UM limite de RAM USADA (em % e/ou GB) dispara UMA acao de limpeza:
    Safe       = Working Sets -> Modified (PADRAO; maior liberacao no dia a dia)
    All        = tudo (Working Sets -> Modified -> Standby) - antes de trocar
                 de tarefa pesada (fechar jogo -> abrir editor)
    SafeStrong = Modified + Standby (nao toca apps abertos; sem stutter)
    Standby    = so a Standby List (leve)
  Com app pesado/jogo aberto, Safe/All viram "SafeStrong" automaticamente.

ESTRUTURA
--------------------------------------------------------------------------------
  scripts/   Codigo (Menu.ps1, LimparRAM-Inteligente.ps1, RamCommon.ps1, ...) + RAMMap.exe
  ui/        index.html (painel grafico; servido por scripts/UI-Server.ps1)
  config/    RamCleanerConfig.json   + RamCleanerConfig.GUIA.jsonc (guia comentado)
  logs/      RAMMap_YYYY-MM-DD.log + monitor-status.json (criados em runtime)
  docs/      README.md  (guia completo)
  Projeto autocontido: scripts, config e logs ficam todos sob C:\Scripts\Ram Otimizador\

DOCUMENTACAO
--------------------------------------------------------------------------------
  Guia completo ........ docs\README.md
  Guia da config ....... config\RamCleanerConfig.GUIA.jsonc

REQUISITOS
--------------------------------------------------------------------------------
  Windows 10/11 + PowerShell 5.1+  |  Administrador  |  RAMMap.exe ja incluso em
  scripts\ (fallback: locais comuns + PATH)
================================================================================
