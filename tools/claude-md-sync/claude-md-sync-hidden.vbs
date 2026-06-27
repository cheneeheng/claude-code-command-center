' Reference copy of the hidden launcher. Install generates one per folder pair as
' claude-md-sync-<hash>-hidden.vbs (gitignored); this template is committed for documentation. Do not edit manually.
' fileA / fileB are replaced with the resolved -FolderA\CLAUDE.md and -FolderB\CLAUDE.md paths.
Set shell = CreateObject("WScript.Shell")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\claude-md-sync.ps1"
fileA = "C:\Path\To\FolderA\CLAUDE.md"
fileB = "C:\Path\To\FolderB\CLAUDE.md"

cmd = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -FileA """ & fileA & """ -FileB """ & fileB & """"
shell.Run cmd, 0, False
