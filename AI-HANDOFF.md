# AI引き継ぎ文書（AI Handoff Document）

> **本文書の目的**: このユーザーとの過去のやり取り（Claude Code セッション）で確立された指示・設定・運用ルールを、別の生成AI（ChatGPT 等）や Claude の再セットアップ・カスタム指示・システムプロンプト最適化にそのまま利用できる形式で集約したもの。
> **想定読者**: AIアシスタント（人間向けの冗長な説明は省略。指示は命令形で記述）。
> **最終更新**: 2026-07-03
> **注意**: ファインチューニング（モデル重みの学習）用データセットではなく、システムプロンプト／カスタム指示／メモリとして注入するための運用知識ベースである。

---

## 1. ユーザープロファイル

| 項目 | 値 |
|---|---|
| 主環境 | Windows（ユーザーディレクトリ: `C:\Users\81909`） |
| シェル | PowerShell / cmd（バッチファイル併用） |
| クラウドストレージ | Proton Drive（`C:\Users\81909\Proton Drive\sub141222\My files\`） |
| メール | sub141222@gmail.com |
| 使用ツール | Claude Code（ローカル + リモート/Web セッション）、Git、GitHub |
| 主リポジトリ | `ryu-o2-1230/research-routine` |
| 言語 | 日本語（応答・ドキュメントは日本語を優先） |

---

## 2. 恒久的なユーザー指示（最優先で遵守）

以下は CLAUDE.md（プロジェクトメモリ）に登録済みの恒久指示。AIはあらゆるタスクでこれを守ること。

1. **ファイル編集・削除前のバックアップ必須**
   - コンピュータ上のファイルを削除または編集する場合、事前にバックアップファイルを保存すること。
   - 実装済みの自動化: Claude Code の PreToolUse フック（`backup-before-edit.ps1`）が Edit/Write 前に対象ファイルを Proton Drive へタイムスタンプ付きでコピーする。保持期間は7日。
   - フックが存在しない環境では、AI自身が編集前に手動でバックアップコピーを作成すること。

2. **新規リポジトリ作成時の権限設定確認**
   - 新規にリポジトリを作成する場合は、`.claude/settings.json` に `"bypassPermissions": true` を追加するか、必ずユーザーに確認すること。
   - 背景: リモート（Web）セッションで権限プロンプトに応答できず作業が止まるのを避けるため。

---

## 3. セキュリティ・権限ポリシー（ユーザーが構築した運用ルール）

ユーザーは「自動実行の利便性」と「破壊的操作の防止」を両立する方針。`enforce-permissions.ps1`（PreToolUse フック、fail-closed 設計）で以下を強制している。AIはフックの有無に関わらず、この方針に沿って行動すること。

### 3.1 禁止（DENY）— 実行してはならない操作
- ファイル・システム破壊: `rm`, `dd`, `mkfs`, `format`, `del /s /q`, `rmdir /s`, `Remove-Item -Recurse/-Force`
- 権限昇格・アカウント操作: `sudo`, `chown`, `chmod 777`, `net user`, `net localgroup`, レジストリ変更（`reg add/delete`）
- プロセス・サービス停止: `kill`, `Stop-Process`, `Stop-Service`
- インフラ破壊: `terraform destroy`, `cdk destroy`, `docker rm`, `docker system prune`
- Git 破壊的操作: `git push --force`, `git reset --hard`, `git clean -f`
- その他: `ssh`, `eval`, `exec`, 出力を隠したバックグラウンド実行

### 3.2 要確認(ASK)— ユーザー確認後にのみ実行
- `git push`, `git reset`
- ネットワークアクセス: `curl`, `wget`, `Invoke-WebRequest`, `Invoke-RestMethod`
- デプロイ・インストール: `terraform apply`, `cdk deploy`, `docker run`, `npm publish`, `pip install`

### 3.3 機密ファイルへのアクセス禁止
`.env`、`.aws/`、`.ssh/`（`id_rsa` 等の秘密鍵）、`.gnupg/`、`credentials.json`、`secrets.*`、`.npmrc`、`.pypirc`、`token(s).json`、`.kube/config`、`.docker/config.json` の読み書きは行わないこと。

---

## 4. バックアップ体制（構築済みインフラ）

| 仕組み | ファイル | 動作 |
|---|---|---|
| 編集前ファイルバックアップ | `backup-before-edit.ps1` | PreToolUse フック。Edit/Write 対象を `Proton Drive\...\claude-backup\file-history\` に元パス構造を維持して `名前_yyyy-MM-dd_HH-mm-ss.拡張子` 形式で保存。7日超の古いバックアップと空ディレクトリは自動削除 |
| CLAUDE.md 日次バックアップ | `backup-claude-md.bat` | `%USERPROFILE%\.claude\CLAUDE.md` を `Proton Drive\...\claude-backup\` へコピー |
| 日次タスク登録 | `setup-backup-task.bat` | Windows タスクスケジューラに「Claude MD Backup」を毎日12:00で登録（要管理者権限） |
| フック設定例 | `claude-settings-example.json` | 上記2フック（enforce-permissions + backup-before-edit）と `bypassPermissions: true` を組み合わせた settings.json のリファレンス |

---

## 5. Claude Code 設定の要点

- リポジトリの `.claude/settings.json` は `"permissions": { "bypassPermissions": true }`（リモートセッションで権限プロンプトによる停止を防ぐため）。
- 安全性はフック側（DENY/ASK パターン）で担保する二層構造。**bypassPermissions を有効にする場合は必ず enforce-permissions 相当のガードを併用すること。**
- フックは Windows 環境では PowerShell（`-ExecutionPolicy Bypass -File`）で起動する。

---

## 6. 経緯（時系列の意思決定ログ）

学習・最適化の文脈で有用な、設定が確立された順序と理由:

1. CLAUDE.md 作成 — 「編集・削除前バックアップ」のユーザー選好を登録。
2. Windows 用バックアップスクリプト追加 — CLAUDE.md 自体を Proton Drive へ日次バックアップ。
3. PreToolUse フックによる自動ファイルバックアップ導入 — 手動バックアップの徹底をフックで自動化。
4. テストファイル（`test-backup.txt`）でフック動作を検証。
5. enforce-permissions フック追加 — 危険コマンドのブロック／リスクコマンドの確認を自動化。
6. リモートセッション向けに bypassPermissions を有効化 — フックによるガードを前提とした利便性向上。
7. 「新規リポジトリ作成時は bypassPermissions を追加するか確認」をメモリに登録。

パターン: **このユーザーは「自動化・省手間」を求めつつ、「破壊的操作・データ喪失」への防御を必ずセットで構築する。** 新しい提案をする際は、利便性向上と同時に安全ガード（バックアップ・ブロックリスト）を提示すると受け入れられやすい。

---

## 7. 他AIへの移植方法

### ChatGPT（カスタム指示 / Projects）へ
「カスタム指示」または Project instructions に以下を貼り付ける:

```text
- 私のファイルを編集・削除する手順を提案する場合、必ず事前バックアップの手順を含めてください。
- 破壊的コマンド（rm, Remove-Item -Recurse, git push --force, git reset --hard, terraform destroy 等）は提案せず、安全な代替手段を示してください。
- ネットワークアクセスやデプロイを伴う手順は、実行前に確認を求める形で提示してください。
- 環境は Windows（PowerShell）。バックアップ先は Proton Drive。
- 回答は日本語で。
```

### Claude（新規セッション / CLAUDE.md）へ
`CLAUDE.md` に以下をそのまま記載する（現行内容と同一）:

```markdown
## User Preferences

- コンピュータのファイルを削除・編集する場合は、事前にバックアップファイルを保存すること
- 新規にリポジトリを作成する場合は、`.claude/settings.json` に `bypassPermissions: true` を追加するか必ずユーザーに確認すること
```

フック込みの完全な環境再現には `claude-settings-example.json` を `.claude/settings.json` に配置し、`backup-before-edit.ps1` と `enforce-permissions.ps1` を `C:\Users\81909\` に置く。

### その他のAIエージェントへ
本文書の第2〜3節を system prompt に注入すれば同等の行動制約を再現できる。第1節（環境情報）と第6節（意思決定パターン）はコンテキストとして任意で追加する。

---

## 8. 既知の制約・注意事項

- フックのパス（`C:\Users\81909\...`）はこのユーザーのローカル環境固有。他マシンへ展開する際はパスを調整すること。
- `enforce-permissions.ps1` は fail-closed（スクリプトがエラーになるとツール実行がブロックされる）。フック変更時は動作確認必須。
- リモート（Linux コンテナ）セッションでは PowerShell フックは動作しない。リモートでは AI 自身が第2〜3節のルールを自律的に守ること。
- バックアップ保持期間は7日。それ以前の版が必要な作業では別途アーカイブを取ること。
