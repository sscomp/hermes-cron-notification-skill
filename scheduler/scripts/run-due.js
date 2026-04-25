#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const hermesHome = process.env.HERMES_HOME;
if (!hermesHome) {
  console.error('Missing HERMES_HOME.');
  process.exit(1);
}

const scheduleFile = path.join(hermesHome, 'cron', 'schedule.json');
const reminderScript = path.join(hermesHome, 'scheduler', 'scripts', 'send-reminder.sh');

function pad(value) {
  return String(value).padStart(2, '0');
}

function localDateKey(date) {
  return [date.getFullYear(), pad(date.getMonth() + 1), pad(date.getDate())].join('-');
}

function ensureStore() {
  const cronDir = path.dirname(scheduleFile);
  fs.mkdirSync(cronDir, { recursive: true });
  if (!fs.existsSync(scheduleFile)) {
    fs.writeFileSync(
      scheduleFile,
      `${JSON.stringify({ jobs: [], lastUpdated: new Date().toISOString() }, null, 2)}\n`
    );
  }
}

function resolveSchedule(job, now) {
  const raw = String(job.scheduleTime || '').trim();
  const recurringMatch = raw.match(/^(?:每日\s*)?(\d{1,2}):(\d{2})$/);

  if (recurringMatch) {
    const dueAt = new Date(now);
    dueAt.setHours(Number(recurringMatch[1]), Number(recurringMatch[2]), 0, 0);
    return {
      recurring: true,
      due: now >= dueAt && job.lastExecutedOn !== localDateKey(now),
    };
  }

  const dueAt = new Date(raw);
  if (Number.isNaN(dueAt.getTime())) {
    return { recurring: false, due: false, invalid: true };
  }

  return {
    recurring: false,
    due: now >= dueAt,
  };
}

ensureStore();

const data = JSON.parse(fs.readFileSync(scheduleFile, 'utf8'));
if (!Array.isArray(data.jobs)) data.jobs = [];

const now = new Date();
let executedCount = 0;

for (const job of data.jobs) {
  if (!job.enabled || job.status === 'executed' || job.status === 'cancelled') continue;

  const schedule = resolveSchedule(job, now);
  if (schedule.invalid) {
    console.error(`Invalid schedule time for ${job.id}: ${job.scheduleTime}`);
    job.status = 'failed';
    job.result = 'invalid-schedule-time';
    job.updatedAt = new Date().toISOString();
    continue;
  }

  if (!schedule.due) continue;

  console.log(`Executing job: ${job.id}`);
  try {
    execFileSync(
      '/bin/bash',
      [
        reminderScript,
        job.userId || '',
        job.message || '',
        job.channel || '',
        job.account || '',
        job.target || '',
      ],
      { stdio: 'inherit' }
    );

    job.status = schedule.recurring ? 'scheduled' : 'executed';
    job.executedAt = new Date().toISOString();
    job.updatedAt = job.executedAt;
    job.result = 'success';
    if (schedule.recurring) {
      job.lastExecutedOn = localDateKey(now);
    }
    executedCount += 1;
  } catch (error) {
    console.error(`Job failed: ${job.id}: ${error.message}`);
    job.status = 'failed';
    job.result = error.message;
    job.updatedAt = new Date().toISOString();
  }
}

data.lastUpdated = new Date().toISOString();
fs.writeFileSync(scheduleFile, `${JSON.stringify(data, null, 2)}\n`);
console.log(`Executed ${executedCount} job(s).`);
