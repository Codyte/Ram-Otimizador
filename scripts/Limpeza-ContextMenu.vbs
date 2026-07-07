' Shim invisivel do menu de contexto (botao direito).
' O registro chama ESTE .vbs via wscript.exe, nao powershell.exe direto:
' "powershell -WindowStyle Hidden" ainda PISCA uma janela azul quando lancado
' pelo Explorer, porque o console e alocado ANTES de o powershell processar o
' -WindowStyle. wscript.exe nao tem console e Run(...,0) ja cria a janela
' escondida -> zero flash ate o prompt do UAC (a elevacao e feita pelo .ps1).
' Arg 0 = acao (WorkingSets|ModifiedPageList|Standby|All|Safe).
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\Limpeza-ContextMenu.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """ -Action " & WScript.Arguments(0)
CreateObject("WScript.Shell").Run cmd, 0, False
