@echo off
set SOURCE=%USERPROFILE%\.claude\CLAUDE.md
set DEST=C:\Users\81909\Proton Drive\sub141222\My files\claude-backup

if not exist "%DEST%" mkdir "%DEST%"

if exist "%SOURCE%" (
    copy /Y "%SOURCE%" "%DEST%\CLAUDE.md"
)
