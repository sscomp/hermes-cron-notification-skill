# hermes-cron-notification-skill

Hermes 專用的定時提醒技能包。

把原本分散的 cron 提醒腳本整理成一個可安裝、可遷移、可重複部署的 Hermes skill package，讓每個 Hermes profile 都能有自己的提醒系統。

## 它是做什麼的

- 幫 Hermes profile 建立自己的提醒排程
- 支援單次提醒與每日提醒
- 自動安裝 skill、scheduler、wrapper 與 `launchd` runner
- 保留舊版排程資料，方便從 `hermes-scheduler` 遷移

一句話理解：
這是一個把「Hermes 定時通知功能」包裝成標準安裝包的 repo。

## 適合誰

- 已經在用 Hermes，想把提醒功能整理成標準模組的人
- 有多個 Hermes profiles，想讓每個 profile 獨立管理提醒的人
- 正在把舊版手工腳本遷移成比較乾淨結構的人

## 功能特色

- `profile-local` 設計，不污染其他 Hermes profiles
- 用 `cron/schedule.json` 保存排程資料
- 用 `scheduler/notification-targets.json` 保存通知目標
- 安裝後提供 `hcron` 指令
- 自動建立 `launchd` agent，每分鐘掃描到期任務
- 目前通知通道以 Telegram 為主

## 快速開始

安裝到指定 profile：

```bash
./scripts/install-profile.sh ~/.hermes/profiles/n2
```

如果只想寫入檔案，不重新載入 `launchd`：

```bash
./scripts/install-profile.sh ~/.hermes/profiles/n2 --no-launchctl
```

## 安裝後你會得到什麼

安裝完成後，profile 內會建立或更新：

- `skills/productivity/hermes-cron-notification`
- `scheduler/scripts/*`
- `cron/schedule.json`
- `scheduler/notification-targets.json`
- `bin/hcron`

系統層會建立：

- `~/Library/LaunchAgents/ai.hermes.cron-notification-<profile>.plist`

## 常用指令

列出排程：

```bash
HERMES_HOME=~/.hermes/profiles/n2 ~/.hermes/profiles/n2/bin/hcron list
```

新增單次提醒：

```bash
HERMES_HOME=~/.hermes/profiles/n2 ~/.hermes/profiles/n2/bin/hcron add 5132341473 "2026-04-27T09:00:00+08:00" "提醒內容"
```

新增每日提醒：

```bash
HERMES_HOME=~/.hermes/profiles/n2 ~/.hermes/profiles/n2/bin/hcron add 5132341473 "每日 09:00" "早安提醒"
```

取消提醒：

```bash
HERMES_HOME=~/.hermes/profiles/n2 ~/.hermes/profiles/n2/bin/hcron cancel <jobId>
```

## Hermes Quick Commands

installer 會把以下 quick commands 合併到 profile 的 `config.yaml`：

- `/remind-add`
- `/remind-list`
- `/remind-cancel`
- `/remind-enable`
- `/remind-disable`

## 排程格式

- 單次提醒：`2026-04-27T09:00:00+08:00`
- 每日提醒：`09:00`
- 每日提醒：`每日 09:00`

## 舊版遷移說明

如果 profile 原本已經有舊版 `hermes-scheduler`：

- 原有 `cron/schedule.json` 會保留
- 原有 `scheduler/notification-targets.json` 會保留
- 舊的 `skills/productivity/hermes-scheduler` 會移除
- 舊的 `ai.hermes.scheduler-<profile>` launch agent 會停用並移除
- 新的 `ai.hermes.cron-notification-<profile>` launch agent 會接手

也就是說，資料保留，執行入口切到新包。

## Repo 結構

- `scripts/install-profile.sh`
  安裝器，負責複製檔案、合併 quick commands、建立 `launchd` agent
- `skill/SKILL.md`
  給 Hermes agent 使用的 skill 說明
- `scheduler/scripts/add-schedule.js`
  排程的新增、查詢、取消、啟停
- `scheduler/scripts/run-due.js`
  掃描到期任務並執行
- `scheduler/scripts/send-reminder.sh`
  實際發送 Telegram 通知
- `scheduler/scripts/hcron.sh`
  profile-local wrapper 入口

## 目前範圍

- 支援 Telegram 通知
- 目標環境是 macOS + `launchd` + Hermes profiles
- 主要面向 Hermes-first 的本地部署情境

## License

MIT
