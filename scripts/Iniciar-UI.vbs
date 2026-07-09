' Shim invisivel do painel grafico (mesmo padrao do Limpeza-ContextMenu.vbs):
' wscript.exe nao tem console e Run(...,0) esconde a janela -> zero flash de
' powershell ate o prompt do UAC (a elevacao e feita pelo UI-Server.ps1).
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\UI-Server.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
CreateObject("WScript.Shell").Run cmd, 0, False
