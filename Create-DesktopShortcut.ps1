# Create Desktop Shortcut for NetSpeedHUD
$WshShell = New-Object -ComObject WScript.Shell
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $DesktopPath "NetSpeed HUD.lnk"

$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "powershell.exe"

# The arguments tell PowerShell to launch the HUD silently
$scriptPath = Join-Path $PSScriptRoot "NetSpeedHUD.ps1"
$Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -HideConsole"

# Use a nice network icon from shell32
$Shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll, 18"
$Shortcut.WorkingDirectory = $PSScriptRoot
$Shortcut.Description = "Launch Live Network Speed Overlay"
$Shortcut.Save()

Write-Output "Successfully created Desktop shortcut at: $ShortcutPath"
