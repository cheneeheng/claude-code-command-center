' Reference copy of the hidden launcher. Install generates one per folder pair as
' settings-sync-<hash>-hidden.vbs (gitignored); this template is committed for documentation. Do not edit manually.
' fileA / fileB are replaced with the resolved -FolderA\settings.json and -FolderB\settings.json paths.
Set shell = CreateObject("WScript.Shell")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\settings-sync.ps1"
fileA = "C:\Path\To\FolderA\settings.json"
fileB = "C:\Path\To\FolderB\settings.json"

cmd = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -FileA """ & fileA & """ -FileB """ & fileB & """"
shell.Run cmd, 0, False
