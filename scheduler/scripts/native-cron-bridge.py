#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def fail(message: str, code: int = 1) -> None:
    print(json.dumps({"success": False, "error": message}, ensure_ascii=False))
    raise SystemExit(code)


def resolve_hermes_agent_dir(hermes_home: Path) -> Path:
    hermes_root = hermes_home.parent.parent
    agent_dir = hermes_root / "hermes-agent"
    if not agent_dir.is_dir():
        fail(f"Hermes agent directory not found: {agent_dir}")
    return agent_dir


def main() -> None:
    hermes_home = os.environ.get("HERMES_HOME", "").strip()
    if not hermes_home:
        fail("Missing HERMES_HOME.")

    home_path = Path(hermes_home).expanduser().resolve()
    agent_dir = resolve_hermes_agent_dir(home_path)
    sys.path.insert(0, str(agent_dir))
    os.environ["HERMES_HOME"] = str(home_path)

    from cron.jobs import create_job, list_jobs, pause_job, remove_job, resume_job  # type: ignore

    action = sys.argv[1] if len(sys.argv) > 1 else ""
    job_id = sys.argv[2] if len(sys.argv) > 2 else ""

    if action == "list":
        jobs = list_jobs(include_disabled=True)
        normalized = []
        for job in jobs:
            normalized.append(
                {
                    "id": job.get("id"),
                    "source": "hermes-native-cron",
                    "name": job.get("name") or job.get("prompt") or job.get("id"),
                    "scheduleTime": job.get("schedule_display")
                    or (job.get("schedule") or {}).get("display")
                    or "",
                    "message": job.get("prompt") or "",
                    "status": job.get("state") or "",
                    "enabled": bool(job.get("enabled", True)),
                    "createdAt": job.get("created_at"),
                    "updatedAt": job.get("last_run_at") or job.get("created_at"),
                    "nextRunAt": job.get("next_run_at"),
                    "lastRunAt": job.get("last_run_at"),
                    "deliver": job.get("deliver"),
                    "origin": job.get("origin"),
                    "native": True,
                }
            )

        print(json.dumps({"success": True, "jobs": normalized}, ensure_ascii=False, indent=2))
        return

    if action == "create":
        if len(sys.argv) < 3:
            fail("Missing create payload.")
        try:
            payload = json.loads(sys.argv[2])
        except json.JSONDecodeError as exc:
            fail(f"Invalid create payload: {exc}")

        user_id = str(payload.get("userId") or "").strip()
        schedule = str(payload.get("schedule") or "").strip()
        message = str(payload.get("message") or "").strip()
        channel = str(payload.get("channel") or "telegram").strip() or "telegram"
        target = str(payload.get("target") or user_id).strip()
        account = str(payload.get("account") or home_path.name).strip() or home_path.name
        user_name = str(payload.get("userName") or f"Telegram {user_id}").strip()

        if channel != "telegram":
            fail(f"Unsupported native remind channel: {channel}")
        if not user_id:
            fail("Missing userId.")
        if not schedule:
            fail("Missing schedule.")
        if not message:
            fail("Missing message.")

        if schedule.startswith("每日 "):
            schedule = schedule[3:].strip()
        if len(schedule) == 5 and schedule[2] == ":":
            hour, minute = schedule.split(":", 1)
            schedule = f"{int(minute)} {int(hour)} * * *"

        prompt = (
            "請在排程時間到達時，直接向使用者發送以下提醒內容，"
            "只輸出提醒本身，不要加入額外說明：\n"
            f"{message}"
        )

        job = create_job(
            prompt=prompt,
            schedule=schedule,
            name=f"提醒通知 - {message[:24]}",
            deliver="origin",
            origin={
                "platform": "telegram",
                "chat_id": target,
                "chat_name": user_name,
                "thread_id": None,
                "account": account,
            },
        )

        print(
            json.dumps(
                {
                    "success": True,
                    "action": "create",
                    "job": {
                        "id": job.get("id"),
                        "source": "hermes-native-cron",
                        "name": job.get("name"),
                        "scheduleTime": job.get("schedule_display"),
                        "message": message,
                        "enabled": job.get("enabled"),
                        "status": job.get("state"),
                        "nextRunAt": job.get("next_run_at"),
                    },
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    if not job_id:
        fail(f"Missing job id for action: {action}")

    if action == "cancel":
        removed = remove_job(job_id)
        if not removed:
            fail(f"Job not found: {job_id}")
        print(
            json.dumps(
                {
                    "success": True,
                    "action": "cancel",
                    "job": {
                        "id": job_id,
                        "source": "hermes-native-cron",
                        "removed": True,
                    },
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    if action == "disable":
        job = pause_job(job_id, reason="disabled from remind command")
        if not job:
            fail(f"Job not found: {job_id}")
        print(
            json.dumps(
                {
                    "success": True,
                    "action": "disable",
                    "job": {
                        "id": job.get("id"),
                        "source": "hermes-native-cron",
                        "name": job.get("name"),
                        "enabled": job.get("enabled"),
                        "status": job.get("state"),
                        "nextRunAt": job.get("next_run_at"),
                    },
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    if action == "enable":
        job = resume_job(job_id)
        if not job:
            fail(f"Job not found: {job_id}")
        print(
            json.dumps(
                {
                    "success": True,
                    "action": "enable",
                    "job": {
                        "id": job.get("id"),
                        "source": "hermes-native-cron",
                        "name": job.get("name"),
                        "enabled": job.get("enabled"),
                        "status": job.get("state"),
                        "nextRunAt": job.get("next_run_at"),
                    },
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    fail(f"Unsupported action: {action}")


if __name__ == "__main__":
    main()
