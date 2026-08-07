# ============================================================
#  毎朝10時に実行される研究サマリー自動生成スクリプト
#  (Windows / PowerShell 版)
#  タスクスケジューラから自動呼び出し
# ============================================================

$ErrorActionPreference = "Stop"

# ── 文字化け対策: ネイティブプロセスとのパイプ入出力をUTF-8に統一 ──
# Windows PowerShell 5.1 の $OutputEncoding 既定値は ASCII のため、
# パイプで claude に渡す日本語がすべて "?" に化ける（2026-06〜07に発生）。
# 注意: スクリプトスコープの代入はネイティブパイプに反映されないため $global: が必須。
$global:OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}

# ── 設定ファイルを読み込む ────────────────────────────────────
$envFile = "$env:USERPROFILE\.research_env.ps1"
if (Test-Path $envFile) {
    . $envFile
} else {
    Write-Error "設定ファイルが見つかりません: $envFile`nsetup.ps1 を先に実行してください。"
    exit 1
}

# ── 変数 ─────────────────────────────────────────────────────
$today      = Get-Date -Format "yyyy-MM-dd"
$yesterday  = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$researchDir = $env:RESEARCH_DIR
$summaryDir  = "$researchDir\daily-summary"
$logFile     = "$summaryDir\logs\$today.log"
$routineDir  = "$env:USERPROFILE\research-routine"

New-Item -ItemType Directory -Force -Path "$summaryDir\logs" | Out-Null

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log "=== 研究サマリー生成開始: $today ==="

# ── 1. 昨日のノートを取得 ────────────────────────────────────
$yesterdayNote = "$researchDir\$yesterday.md"
if (Test-Path $yesterdayNote) {
    $yesterdayContent = Get-Content $yesterdayNote -Encoding UTF8 -Raw
    Log "昨日のノートを読み込みました: $yesterdayNote"
} else {
    $yesterdayContent = "（昨日のノートが見つかりませんでした: $yesterday.md）"
    Log "WARNING: 昨日のノートが見つかりません"
}

# ── 2. GitHub Issues を取得 ──────────────────────────────────
$githubIssuesText = ""
if ($env:GITHUB_REPO -ne "" -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    Log "GitHub Issues を取得中..."
    try {
        # gh はオープンIssueが0件のとき通知をstderrに出すため、EAP=Stop下では
        # 例外扱いになり「取得失敗」と誤記録される。この呼び出しの間だけ緩める。
        $ErrorActionPreference = "Continue"
        $githubIssuesText = gh issue list `
            --repo $env:GITHUB_REPO `
            --state open `
            --limit 20 `
            --json "number,title,labels,updatedAt" `
            --jq '.[] | "- #\(.number) \(.title) [labels: \(.labels | map(.name) | join(","))] (更新: \(.updatedAt[:10]))"' `
            2>>$logFile
        Log "GitHub Issues 取得完了"
    } catch {
        $githubIssuesText = "（GitHub Issues の取得に失敗しました）"
        Log "WARNING: GitHub Issues 取得失敗"
    } finally {
        $ErrorActionPreference = "Stop"
    }
    if (-not $githubIssuesText) { $githubIssuesText = "（オープンIssueなし）" }
} else {
    $githubIssuesText = "（GitHub CLIが未設定またはリポジトリ未指定のためスキップ）"
    Log "GitHub Issues スキップ"
}

# ── 3. Claude Code でサマリー生成 ────────────────────────────
Log "Claude Code でサマリーを生成中..."

$now = Get-Date -Format "yyyy-MM-dd HH:mm"
$prompt = @"
あなたは研究者のアシスタントです。以下の情報をもとに、日本語で研究サマリーを作成してください。

## 昨日の研究ノート ($yesterday)
$yesterdayContent

## GitHubのオープンIssues
$githubIssuesText

## 出力形式

以下のMarkdown形式で出力してください（コードブロックやプレフィックスは不要です）：

# 研究サマリー: $today

## 📝 昨日の成果まとめ ($yesterday)
昨日の研究ノートを3〜5点の箇条書きで簡潔にまとめてください。

## 🔍 主要な発見・進捗
昨日のノートから特に重要な発見や進捗を記述してください。

## ✅ 今日更新すべきタスク
GitHubのオープンIssuesと昨日の研究内容を踏まえて、今日取り組むべきタスクを優先順位付きで3〜7件リストアップしてください。
形式: - [ ] タスク内容 (#Issue番号 があれば記載)

## 💡 提案・メモ
昨日の内容から今後の研究に役立ちそうなアイデアや注意点があれば記述してください。

---
*自動生成: $now JST*
"@

# 一時ファイルにプロンプトを書き出して claude に渡す
$tmpPrompt = [System.IO.Path]::GetTempFileName() + ".txt"
$prompt | Set-Content -Encoding UTF8 $tmpPrompt

try {
    $summaryContent = Get-Content $tmpPrompt -Raw | claude -p --dangerously-skip-permissions --max-turns 20 2>>$logFile
} finally {
    Remove-Item $tmpPrompt -ErrorAction SilentlyContinue
}

if (-not $summaryContent) {
    Log "ERROR: サマリー生成に失敗しました"
    exit 1
}
Log "サマリー生成完了"

# ── 4. Markdown ファイルに保存 ────────────────────────────────
$outputFile = "$summaryDir\$today.md"
$summaryContent | Set-Content -Encoding UTF8 $outputFile
Log "サマリーを保存しました: $outputFile"

# ── 5. 今日のノートテンプレートを作成 ────────────────────────
$todayNote = "$researchDir\$today.md"
if (-not (Test-Path $todayNote)) {
    @"
# 研究ノート: $today

## 今日の目標
<!-- 今日取り組むことを記載 -->

## 作業記録

### 午前

### 午後

## 成果・気づき

## 明日に向けて

"@ | Set-Content -Encoding UTF8 $todayNote
    Log "今日のノートテンプレートを作成しました: $todayNote"
}

# ── 6. Gmail でメール送信 ─────────────────────────────────────
if ($env:EMAIL_TO -ne "" -and $env:EMAIL_FROM -ne "" -and $env:GMAIL_APP_PASSWORD -ne "") {
    Log "メール送信中..."
    $subject   = "【研究サマリー】$today"
    $plainText = $summaryContent -replace '^#{1,3} ', '' -replace '\[ \]', '☐' -replace '\[x\]', '☑'

    # 本文はコマンドライン引数ではなく一時ファイルで渡す
    # （引用符・改行を含む本文が引数解析を壊してargparseのusageエラーになるため）
    $tmpBody = [System.IO.Path]::GetTempFileName() + ".txt"
    $plainText | Set-Content -Encoding UTF8 $tmpBody
    try {
        python "$routineDir\send_email.py" --to $env:EMAIL_TO --from-addr $env:EMAIL_FROM --subject $subject --body-file $tmpBody --smtp-server $env:SMTP_SERVER --smtp-port $env:SMTP_PORT --password $env:GMAIL_APP_PASSWORD 2>>$logFile
        Log "メール送信完了: $($env:EMAIL_TO)"
    } catch {
        Log "WARNING: メール送信に失敗しました: $_"
    } finally {
        Remove-Item $tmpBody -ErrorAction SilentlyContinue
    }
} else {
    Log "メール設定が不完全なためスキップ"
}

Log "=== 完了 ==="
Log "  サマリー:       $outputFile"
Log "  今日のノート:   $todayNote"



