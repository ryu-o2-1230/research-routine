@echo off
REM CLAUDE.md バックアップタスクを登録するスクリプト
REM 管理者権限で実行してください

set SCRIPT_PATH=%~dp0backup-claude-md.bat

schtasks /create /tn "Claude MD Backup" /tr "\"%SCRIPT_PATH%\"" /sc daily /st 12:00 /f

echo タスク "Claude MD Backup" を登録しました（毎日12:00に実行）
pause
