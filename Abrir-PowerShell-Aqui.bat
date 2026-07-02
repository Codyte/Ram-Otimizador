@echo off
REM Abre PowerShell como ADMIN nesta pasta
REM Clique direito > Executar como administrador

PowerShell -NoExit -Command "Set-Location '%~dp0scripts'"
