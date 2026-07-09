@echo off
REM ====================================================================
REM  LIMPADOR INTELIGENTE DE RAM - Ponto de entrada unico
REM  Padrao: abre o Painel grafico (UI), que tem tudo (limpeza, tarefa,
REM  perfis, configuracoes, logs). Para o menu classico no console:
REM      INICIAR.bat cmd
REM ====================================================================
title Limpador Inteligente de RAM

if /i "%~1"=="cmd" goto menu

REM --- Painel grafico: shim vbs sem console; UI-Server.ps1 auto-eleva (UAC) ---
wscript.exe //nologo "%~dp0scripts\Iniciar-UI.vbs"
exit /b

:menu
REM --- Verifica privilegios de admin; se nao tiver, re-executa elevado ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de Administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList 'cmd'"
    exit /b
)

cd /d "%~dp0scripts"
REM Sem -NoExit: ao escolher "0 - Sair" no menu a janela fecha em vez de
REM largar o usuario num prompt do PowerShell. Se o menu quebrar, pausa
REM para dar tempo de ler o erro antes de fechar.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Menu.ps1"
if %errorlevel% neq 0 (
    echo.
    echo O menu terminou com erro %errorlevel%.
    pause
)
