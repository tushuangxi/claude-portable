' ClaudePortable.vbs — Windows launcher
' Opens ClaudePortable.bat in a cmd window without showing the VBS host
' Handles both system/ and root directory layouts

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' Resolve portable root
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
If LCase(fso.GetFolder(scriptDir).Name) = "system" Then
    portableDir = fso.GetParentFolderName(scriptDir)
Else
    portableDir = scriptDir
End If

batFile = portableDir & "\ClaudePortable.bat"
If Not fso.FileExists(batFile) Then
    ' Try system/ subdirectory
    batFile = portableDir & "\system\ClaudePortable.bat"
End If

If fso.FileExists(batFile) Then
    ' Use /D to ignore AutoRun registry, /K to keep window open
    shell.Run "cmd.exe /D /K """ & batFile & """", 1, False
Else
    MsgBox "找不到 ClaudePortable.bat" & vbCrLf & _
           "路径: " & portableDir, vbCritical, "Claude Portable"
End If
