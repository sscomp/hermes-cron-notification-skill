# Hermes Cron Notification

## 描述
這個技能讓 Hermes agent 設定 profile-local 的定時提醒通知。它使用每個 profile 自己的 `cron/schedule.json` 與 `scheduler/notification-targets.json`，並透過 launchd 每分鐘掃描一次到期任務。

目前這個技能的通知通道以 Telegram 為主。

## 觸發場景
- 使用者要求「提醒我...」
- 使用者要求「幫我定時通知...」
- 使用者要求「某個時間叫我...」
- 使用者需要每日固定時間提醒

## 重要規則
- 只操作目前 profile 的 `HERMES_HOME`。
- 不要把排程寫去別的 Hermes profile。
- 若使用者在 Telegram 對話中提出要求，優先使用當前 Telegram user id 或 chat id。
- 若沒有可用來源 id，可以使用主要使用者 Telegram id 作為 fallback，再明確告知使用者通知對象。
- 單次提醒時間請使用台灣時間 ISO 格式，例如 `2026-04-27T09:00:00+08:00`。
- 每日提醒可用 `HH:mm` 或 `每日 HH:mm`。
- 回覆時應明確說明 job id、預計時間、通知對象。
- 不要輸出 bot token 或 `.env` 內容。

## 建議操作

新增排程：

```bash
HERMES_HOME="$HERMES_HOME" "$HERMES_HOME/bin/hcron" add "5132341473" "2026-04-27T09:00:00+08:00" "提醒內容"
```

指定通知 target：

```bash
HERMES_HOME="$HERMES_HOME" "$HERMES_HOME/bin/hcron" add "5132341473" "每日 09:00" "早安提醒" --channel=telegram --target=5132341473
```

查詢排程：

```bash
HERMES_HOME="$HERMES_HOME" "$HERMES_HOME/bin/hcron" list
```

取消排程：

```bash
HERMES_HOME="$HERMES_HOME" "$HERMES_HOME/bin/hcron" cancel "<jobId>"
```

## 驗證
新增、取消、啟用或停用排程後，必須查詢一次：

```bash
cat "$HERMES_HOME/cron/schedule.json"
```

若要手動執行一次 scheduler tick：

```bash
HERMES_HOME="$HERMES_HOME" "$HERMES_HOME/bin/hcron" tick
```
