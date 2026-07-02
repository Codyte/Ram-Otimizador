@echo off
REM ====================================================================
REM  LIMPADOR INTELIGENTE DE RAM - Ponto de entrada unico
REM  Auto-eleva para Administrador e abre a Central de Controle (Menu).
REM ====================================================================
title Limpador Inteligente de RAM

REM --- Verifica privilegios de admin; se nao tiver, re-executa elevado ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de Administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
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
