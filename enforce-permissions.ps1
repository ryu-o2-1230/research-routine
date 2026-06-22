# enforce-permissions.ps1
# PreToolUse hook: dangerous commands are blocked, risky commands require confirmation
# Design: fail-closed (if this script errors, tool is blocked)

param()

$ErrorActionPreference = "Stop"

try {
    $inputText = [Console]::In.ReadToEnd()
    $json = $inputText | ConvertFrom-Json
} catch {
    Write-Error "enforce-permissions: Failed to parse input JSON"
    exit 2
}

$toolName = $json.tool_name
$toolInput = $json.tool_input

function Deny($reason) {
    $result = @{
        hookSpecificOutput = @{
            permissionDecision = "deny"
            reason = $reason
        }
    } | ConvertTo-Json -Depth 3
    Write-Output $result
    exit 0
}

function Ask($reason) {
    $result = @{
        hookSpecificOutput = @{
            permissionDecision = "ask"
            reason = $reason
        }
    } | ConvertTo-Json -Depth 3
    Write-Output $result
    exit 0
}

# --- Bash tool checks ---
if ($toolName -eq "Bash") {
    $cmd = $toolInput.command
    if (-not $cmd) { exit 0 }

    # Normalize: remove quotes and backslashes to prevent bypass via quote splitting
    $normalizedCmd = $cmd -replace "['""`\\]", ""

    # === DENY patterns (destructive / privilege escalation) ===
    $denyPatterns = @(
        @{ pattern = '\brm\b'; reason = "rm is blocked" }
        @{ pattern = '\bsudo\b'; reason = "sudo is blocked" }
        @{ pattern = '\bkill\b'; reason = "kill is blocked" }
        @{ pattern = '\bdd\b'; reason = "dd is blocked" }
        @{ pattern = '\bmkfs\b'; reason = "mkfs is blocked" }
        @{ pattern = '\bformat\b.*[A-Z]:'; reason = "format drive is blocked" }
        @{ pattern = '\bdel\b.*(/s|/q|\\)'; reason = "del with flags is blocked" }
        @{ pattern = '\brmdir\b.*(/s|/q)'; reason = "rmdir /s is blocked" }
        @{ pattern = '\brd\b.*(/s|/q)'; reason = "rd /s is blocked" }
        @{ pattern = 'Remove-Item.*-Recurse'; reason = "Remove-Item -Recurse is blocked" }
        @{ pattern = 'Remove-Item.*-Force'; reason = "Remove-Item -Force is blocked" }
        @{ pattern = '\bchmod\s+777\b'; reason = "chmod 777 is blocked" }
        @{ pattern = '\bchown\b'; reason = "chown is blocked" }
        @{ pattern = '\beval\b'; reason = "eval is blocked" }
        @{ pattern = '\bexec\b'; reason = "exec is blocked" }
        @{ pattern = 'cdk\s+destroy'; reason = "cdk destroy is blocked" }
        @{ pattern = 'terraform\s+destroy'; reason = "terraform destroy is blocked" }
        @{ pattern = '\bdocker\s+rm\b'; reason = "docker rm is blocked" }
        @{ pattern = '\bdocker\s+system\s+prune\b'; reason = "docker system prune is blocked" }
        @{ pattern = 'git\s+push.*--force'; reason = "git push --force is blocked" }
        @{ pattern = 'git\s+reset\s+--hard'; reason = "git reset --hard is blocked" }
        @{ pattern = 'git\s+clean\s+-f'; reason = "git clean -f is blocked" }
        @{ pattern = '\bssh\b'; reason = "ssh is blocked" }
        @{ pattern = '>\s*/dev/null.*2>&1.*&'; reason = "background suppressed command is blocked" }
        @{ pattern = '\bnet\s+user\b'; reason = "net user is blocked" }
        @{ pattern = '\bnet\s+localgroup\b'; reason = "net localgroup is blocked" }
        @{ pattern = '\breg\s+(delete|add)\b'; reason = "registry modification is blocked" }
        @{ pattern = 'Stop-Process'; reason = "Stop-Process is blocked" }
        @{ pattern = 'Stop-Service'; reason = "Stop-Service is blocked" }
    )

    foreach ($entry in $denyPatterns) {
        if ($normalizedCmd -match $entry.pattern) {
            Deny $entry.reason
        }
    }

    # === ASK patterns (risky but sometimes needed) ===
    $askPatterns = @(
        @{ pattern = '\bgit\s+push\b'; reason = "git push requires confirmation" }
        @{ pattern = '\bgit\s+reset\b'; reason = "git reset requires confirmation" }
        @{ pattern = '\bcurl\b'; reason = "curl requires confirmation" }
        @{ pattern = '\bwget\b'; reason = "wget requires confirmation" }
        @{ pattern = '\bInvoke-WebRequest\b'; reason = "Invoke-WebRequest requires confirmation" }
        @{ pattern = '\bInvoke-RestMethod\b'; reason = "Invoke-RestMethod requires confirmation" }
        @{ pattern = 'terraform\s+apply'; reason = "terraform apply requires confirmation" }
        @{ pattern = 'cdk\s+deploy'; reason = "cdk deploy requires confirmation" }
        @{ pattern = '\bdocker\s+run\b'; reason = "docker run requires confirmation" }
        @{ pattern = '\bnpm\s+publish\b'; reason = "npm publish requires confirmation" }
        @{ pattern = '\bpip\s+install\b'; reason = "pip install requires confirmation" }
    )

    foreach ($entry in $askPatterns) {
        if ($normalizedCmd -match $entry.pattern) {
            Ask $entry.reason
        }
    }
}

# --- File operation checks (Read/Write/Edit) ---
if ($toolName -in @("Read", "Write", "Edit")) {
    $filePath = $toolInput.file_path
    if (-not $filePath) { $filePath = $toolInput.path }
    if (-not $filePath) { exit 0 }

    $normalizedPath = $filePath -replace "\\", "/"

    # Sensitive file patterns
    $denyFilePatterns = @(
        @{ pattern = '\.env($|\.)'; reason = ".env file access is blocked" }
        @{ pattern = '\.aws/'; reason = ".aws/ directory access is blocked" }
        @{ pattern = '\.ssh/'; reason = ".ssh/ directory access is blocked" }
        @{ pattern = 'id_rsa'; reason = "SSH private key access is blocked" }
        @{ pattern = 'id_ed25519'; reason = "SSH private key access is blocked" }
        @{ pattern = 'id_ecdsa'; reason = "SSH private key access is blocked" }
        @{ pattern = '\.gnupg/'; reason = ".gnupg/ directory access is blocked" }
        @{ pattern = 'credentials\.json'; reason = "credentials file access is blocked" }
        @{ pattern = 'secrets?\.(json|ya?ml|toml)'; reason = "secrets file access is blocked" }
        @{ pattern = '\.npmrc'; reason = ".npmrc access is blocked" }
        @{ pattern = '\.pypirc'; reason = ".pypirc access is blocked" }
        @{ pattern = 'token(s)?\.json'; reason = "token file access is blocked" }
        @{ pattern = '\.kube/config'; reason = "kubeconfig access is blocked" }
        @{ pattern = '\.docker/config\.json'; reason = "docker config access is blocked" }
    )

    foreach ($entry in $denyFilePatterns) {
        if ($normalizedPath -match $entry.pattern) {
            Deny $entry.reason
        }
    }
}

exit 0
