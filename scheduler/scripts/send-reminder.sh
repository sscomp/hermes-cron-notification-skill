#!/usr/bin/env bash

set -euo pipefail

if [ -z "${HERMES_HOME:-}" ]; then
  echo "Missing HERMES_HOME."
  exit 1
fi

USER_ID="${1:-}"
MESSAGE="${2:-}"
CHANNEL="${3:-telegram}"
ACCOUNT="${4:-}"
TARGET="${5:-}"
ENV_FILE="$HERMES_HOME/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE"
  exit 1
fi

if [ "$CHANNEL" != "telegram" ] && [ -n "$CHANNEL" ]; then
  echo "Unsupported reminder channel: $CHANNEL"
  exit 1
fi

TOKEN="$(awk -F= '/^TELEGRAM_BOT_TOKEN=/{print $2; exit}' "$ENV_FILE" | tr -d '\r')"
FINAL_TARGET="${TARGET:-$USER_ID}"

if [ -z "$TOKEN" ]; then
  echo "Missing TELEGRAM_BOT_TOKEN in $ENV_FILE"
  exit 1
fi

if [ -z "$FINAL_TARGET" ]; then
  echo "Missing reminder target."
  exit 1
fi

RESPONSE="$(curl -sS -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${FINAL_TARGET}" \
  -d "text=${MESSAGE}")"

if echo "$RESPONSE" | grep -q '"ok":true'; then
  echo "Reminder sent via Telegram account ${ACCOUNT:-default} to ${FINAL_TARGET}."
else
  echo "Telegram send failed: $RESPONSE"
  exit 1
fi
