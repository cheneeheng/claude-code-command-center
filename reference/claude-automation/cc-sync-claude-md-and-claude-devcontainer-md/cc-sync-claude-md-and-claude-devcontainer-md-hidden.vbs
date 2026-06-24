Set shell = CreateObject("WScript.Shell")
home = shell.ExpandEnvironmentStrings("%USERPROFILE%")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
scriptPath = scriptDir & "\cc-sync-claude-md-and-claude-devcontainer-md.ps1"
fileA = home & "\.claude\CLAUDE.md"
fileB = home & "\.claude_devcontainer\CLAUDE.md"

cmd = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -FileA """ & fileA & """ -FileB """ & fileB & """"
shell.Run cmd, 0, False
