#!/usr/bin/env python3
"""
Gmail SMTP でサマリーメールを送信するスクリプト
"""
import argparse
import smtplib
import sys
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime


def send_email(to: str, from_addr: str, subject: str, body: str,
               smtp_server: str, smtp_port: int, password: str) -> None:
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to

    # プレーンテキスト
    part_plain = MIMEText(body, "plain", "utf-8")

    # HTML版（Markdownを簡易的にHTMLに変換）
    html_body = markdown_to_html(body)
    part_html = MIMEText(html_body, "html", "utf-8")

    msg.attach(part_plain)
    msg.attach(part_html)  # HTML を優先表示

    # local_hostname を明示指定する。このPCの自動検出FQDNは
    # "DESKTOP-xxx.flets-east.jp. iptvf.jp" のようにスペースを含む不正な値になり、
    # GmailがEHLOを 501 invalid で拒否する（STARTTLS/AUTH未対応エラーの真因）。
    local_host = "[127.0.0.1]"
    if smtp_port == 465:
        # 暗黙TLS（ポート465）。STARTTLSが使えない環境向け
        with smtplib.SMTP_SSL(smtp_server, smtp_port, local_hostname=local_host) as server:
            server.ehlo()
            server.login(from_addr, password)
            server.sendmail(from_addr, [to], msg.as_string())
    else:
        with smtplib.SMTP(smtp_server, smtp_port, local_hostname=local_host) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            server.login(from_addr, password)
            server.sendmail(from_addr, [to], msg.as_string())
    # 成功メッセージはstdoutへ（stderrに出すとPowerShell側の 2>> リダイレクト+
    # ErrorActionPreference=Stop で成功時にも例外扱いになるため）
    print(f"メール送信完了: {to}")


def markdown_to_html(text: str) -> str:
    """Markdownを簡易的にHTMLに変換"""
    import re
    lines = text.split("\n")
    html_lines = []
    in_list = False

    for line in lines:
        # 見出し
        if line.startswith("### "):
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append(f"<h3>{line[4:]}</h3>")
        elif line.startswith("## "):
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append(f"<h2 style='color:#2c5282;border-bottom:1px solid #e2e8f0;padding-bottom:4px'>{line[3:]}</h2>")
        elif line.startswith("# "):
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append(f"<h1 style='color:#1a202c'>{line[2:]}</h1>")
        # チェックボックス
        elif line.startswith("- [ ] "):
            if not in_list:
                html_lines.append("<ul style='list-style:none;padding-left:0'>")
                in_list = True
            html_lines.append(f"<li>☐ {line[6:]}</li>")
        elif line.startswith("- [x] "):
            if not in_list:
                html_lines.append("<ul style='list-style:none;padding-left:0'>")
                in_list = True
            html_lines.append(f"<li style='color:gray;text-decoration:line-through'>☑ {line[6:]}</li>")
        # 箇条書き
        elif line.startswith("- ") or line.startswith("* "):
            if not in_list:
                html_lines.append("<ul>")
                in_list = True
            html_lines.append(f"<li>{line[2:]}</li>")
        # 水平線
        elif line.strip() == "---":
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append("<hr style='border:none;border-top:1px solid #e2e8f0;margin:16px 0'>")
        # 空行
        elif line.strip() == "":
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append("<br>")
        # 通常テキスト（bold）
        else:
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            # **bold** を <strong> に変換
            line = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', line)
            # *italic* を <em> に変換
            line = re.sub(r'\*(.+?)\*', r'<em>\1</em>', line)
            # `code` を <code> に変換
            line = re.sub(r'`(.+?)`', r'<code style="background:#f7fafc;padding:1px 4px;border-radius:3px">\1</code>', line)
            html_lines.append(f"<p style='margin:4px 0'>{line}</p>")

    if in_list:
        html_lines.append("</ul>")

    html_content = "\n".join(html_lines)
    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
             max-width:680px;margin:0 auto;padding:24px;color:#2d3748;line-height:1.6">
{html_content}
</body>
</html>"""


def main():
    parser = argparse.ArgumentParser(description="Gmail SMTP でメール送信")
    parser.add_argument("--to", required=True)
    parser.add_argument("--from-addr", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--body", default=None)
    parser.add_argument("--body-file", default=None,
                        help="本文をファイルから読む（UTF-8）。引用符・改行を含む本文はこちらを推奨")
    parser.add_argument("--smtp-server", default="smtp.gmail.com")
    parser.add_argument("--smtp-port", type=int, default=587)
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    if args.body_file:
        # utf-8-sig: PowerShellのSet-Content -Encoding UTF8が付けるBOMを吸収
        with open(args.body_file, "r", encoding="utf-8-sig") as f:
            body = f.read()
    elif args.body is not None:
        body = args.body
    else:
        parser.error("--body または --body-file のいずれかを指定してください")

    send_email(
        to=args.to,
        from_addr=args.from_addr,
        subject=args.subject,
        body=body,
        smtp_server=args.smtp_server,
        smtp_port=args.smtp_port,
        password=args.password,
    )


if __name__ == "__main__":
    main()
