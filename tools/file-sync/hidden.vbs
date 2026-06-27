' Reference copy of the hidden launcher. Install generates one per (file, folder pair) as
' file-sync-<hash>-hidden.vbs (gitignored); this template is committed for documentation. Do not edit manually.
' fileA / fileB / -Strategy / -ExcludePaths are filled in from the install args.
Set shell = CreateObject("WScript.Shell")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\sync-engine.ps1"
fileA = "C:\Path\To\FolderA\settings.json"
fileB = "C:\Path\To\FolderB\settings.json"

cmd = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -FileA """ & fileA & """ -FileB """ & fileB & """ -Strategy json-merge -ExcludePaths ""statusLine.command"""
shell.Run cmd, 0, False
