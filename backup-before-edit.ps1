# Claude Code PreToolUse hook script
# Backs up files before Edit/Write operations to Proton Drive
# Called with tool input JSON via stdin

param()

$BACKUP_ROOT = "C:\Users\81909\Proton Drive\sub141222\My files\claude-backup\file-history"
$RETENTION_DAYS = 7

# Read stdin (tool input JSON)
$input = $Input | Out-String

# Extract file path from JSON (handles file_path or path fields)
$filePath = $null
if ($input -match '"file_path"\s*:\s*"([^"]+)"') {
    $filePath = $Matches[1]
} elseif ($input -match '"path"\s*:\s*"([^"]+)"') {
    $filePath = $Matches[1]
}

# If no file path found or file doesn't exist, exit
if (-not $filePath -or -not (Test-Path $filePath)) {
    exit 0
}

# Create backup directory structure mirroring original path
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$relativePath = $filePath -replace '^[A-Za-z]:\\', ''
$backupDir = Join-Path $BACKUP_ROOT (Split-Path $relativePath -Parent)
$fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
$extension = [System.IO.Path]::GetExtension($filePath)
$backupName = "${fileName}_${timestamp}${extension}"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

# Copy file to backup
Copy-Item -Path $filePath -Destination (Join-Path $backupDir $backupName) -Force

# Cleanup: remove backups older than retention period
Get-ChildItem -Path $BACKUP_ROOT -Recurse -File |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RETENTION_DAYS) } |
    Remove-Item -Force

# Remove empty directories
Get-ChildItem -Path $BACKUP_ROOT -Recurse -Directory |
    Where-Object { (Get-ChildItem $_.FullName -Recurse -File).Count -eq 0 } |
    Remove-Item -Force -Recurse 2>$null

exit 0
