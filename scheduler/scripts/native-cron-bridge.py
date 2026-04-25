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

    from cron.jobs import list_jobs, pause_job, remove_job, resume_job  # type: ignore

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
