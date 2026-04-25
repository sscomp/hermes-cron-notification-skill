#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const hermesHome =
  process.env.HERMES_HOME ||
  process.argv.find((arg) => arg.startsWith('--home='))?.slice(7);

if (!hermesHome) {
  console.error(
    'Missing HERMES_HOME. Run inside a Hermes profile or pass --home=/path/to/profile.'
  );
  process.exit(1);
}

const filteredArgs = process.argv.filter((arg) => !arg.startsWith('--home='));
const args = filteredArgs.slice(2);
const action = args[0];

const profileName = path.basename(hermesHome);
const cronDir = path.join(hermesHome, 'cron');
const scheduleFile = path.join(cronDir, 'schedule.json');
const targetsFile = path.join(hermesHome, 'scheduler', 'notification-targets.json');
const hermesRoot = path.resolve(hermesHome, '..', '..');
const nativeBridge = path.join(hermesHome, 'scheduler', 'scripts', 'native-cron-bridge.py');
const nativePython =
  process.env.HERMES_PYTHON || path.join(hermesRoot, 'hermes-agent', 'venv', 'bin', 'python');

function readJson(file, fallback) {
  if (!fs.existsSync(file)) return fallback;
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}

function nowIso() {
  return new Date().toISOString();
}

function normalizeSchedule(raw) {
  const value = String(raw || '').trim();
  if (/^(?:每日\s*)?\d{1,2}:\d{2}$/.test(value)) return value;

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid schedule time: ${value}`);
  }
  return value;
}

function loadStore() {
  const data = readJson(scheduleFile, { jobs: [], lastUpdated: nowIso() });
  if (!Array.isArray(data.jobs)) data.jobs = [];
  return data;
}

function reminderView(job) {
  return {
    ...job,
    source: 'hermes-cron-notification',
    native: false,
  };
}

function runNativeBridge(actionName, maybeJobId) {
  if (!fs.existsSync(nativeBridge) || !fs.existsSync(nativePython)) {
    if (actionName === 'list') return { success: true, jobs: [] };
    return { success: false, error: 'Native Hermes cron bridge is unavailable.' };
  }

  try {
    const args = [nativeBridge, actionName];
    if (maybeJobId) args.push(maybeJobId);
    const raw = execFileSync(nativePython, args, {
      env: { ...process.env, HERMES_HOME: hermesHome },
      encoding: 'utf8',
    });
    return JSON.parse(raw);
  } catch (error) {
    const stderr = error.stderr ? String(error.stderr) : '';
    const stdout = error.stdout ? String(error.stdout) : '';
    const message = stderr.trim() || stdout.trim() || error.message;
    return { success: false, error: message };
  }
}

function parseFlags(items) {
  const flags = {};
  for (const item of items) {
    const match = item.match(/^--([^=]+)=(.*)$/);
    if (match) flags[match[1]] = match[2];
  }
  return flags;
}

function positionalArgs(items) {
  return items.filter((item) => !item.startsWith('--'));
}

function defaultUserIdFromTargets() {
  const registry = readJson(targetsFile, { users: {} });
  if (registry.users?.['5132341473']?.[profileName]) return '5132341473';

  const entries = Object.entries(registry.users || {});
  for (const [userId, profiles] of entries) {
    if (profiles && profiles[profileName]) return userId;
  }
  return '5132341473';
}

function extractScheduleAndMessage(text) {
  const patterns = [
    /(每日\s*\d{1,2}:\d{2})/,
    /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?)/,
    /\b(\d{1,2}:\d{2})\b/,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) continue;
    const schedule = match[1].replace(/\s+/g, ' ').trim();
    const after = text.slice(match.index + match[0].length).trim();
    const before = text.slice(0, match.index).trim();
    const message = after || before.replace(/^(提醒我|提醒|幫我|訂一個|新增|建立)\s*/u, '').trim();
    if (message) {
      return { schedule, message };
    }
  }

  return null;
}

function resolveAddInput(items) {
  const flags = parseFlags(items);
  const positionals = positionalArgs(items);

  if (!positionals.length) {
    throw new Error('Missing arguments for add: time, message');
  }

  if (positionals.length >= 3) {
    const first = String(positionals[0]).trim();
    const second = String(positionals[1]).trim();
    const looksLikeUserId = /^\d{6,}$/.test(first);
    const looksLikeSchedule =
      /^(?:每日\s*)?\d{1,2}:\d{2}$/.test(second) ||
      /^\d{4}-\d{2}-\d{2}T/.test(second);

    if (looksLikeUserId && looksLikeSchedule) {
      return {
        userId: first,
        time: second,
        message: positionals.slice(2).join(' ').trim(),
        flags,
      };
    }
  }

  const parsed = extractScheduleAndMessage(positionals.join(' ').trim());
  if (!parsed) {
    throw new Error(
      'Missing arguments for add: provide "<time> <message>" or "<userId> <time> <message>"'
    );
  }

  return {
    userId: flags.userId || flags.target || defaultUserIdFromTargets(),
    time: parsed.schedule,
    message: parsed.message,
    flags,
  };
}

function resolveTarget(userId, explicit) {
  if (explicit.target || explicit.channel || explicit.account) {
    return {
      channel: explicit.channel || 'telegram',
      account: explicit.account || profileName,
      target: explicit.target || userId,
    };
  }

  const registry = readJson(targetsFile, { users: {} });
  const profileTarget = registry.users?.[userId]?.[profileName];
  if (profileTarget) {
    return {
      channel: profileTarget.channel || 'telegram',
      account: profileTarget.account || profileName,
      target: profileTarget.target || userId,
    };
  }

  return {
    channel: 'telegram',
    account: profileName,
    target: userId,
  };
}

if (!action || !['add', 'list', 'cancel', 'enable', 'disable'].includes(action)) {
  console.log('Usage: add-schedule.js <add|list|cancel|enable|disable> [args]');
  console.log(
    'Add: add-schedule.js add <userId> <ISO_TIME|HH:mm|每日 HH:mm> <message> [--target=id] [--channel=telegram] [--account=name]'
  );
  process.exit(action ? 1 : 0);
}

const data = loadStore();

if (action === 'add') {
  try {
    const input = resolveAddInput(args.slice(1));
    const target = resolveTarget(input.userId, input.flags);
    const nativeResult = runNativeBridge(
      'create',
      JSON.stringify({
        userId: input.userId,
        schedule: normalizeSchedule(input.time),
        message: input.message,
        channel: target.channel,
        account: target.account,
        target: target.target,
        userName: input.flags.userName || '',
      })
    );

    if (!nativeResult.success) {
      console.error(nativeResult.error || 'Failed to create remind job.');
      process.exit(1);
    }

    console.log(JSON.stringify(nativeResult.job, null, 2));
    process.exit(0);
  } catch (error) {
    console.error(error.message || String(error));
    process.exit(1);
  }
}

if (action === 'list') {
  const native = runNativeBridge('list');
  const combined = [...data.jobs.map(reminderView), ...(native.jobs || [])];
  console.log(JSON.stringify(combined, null, 2));
  process.exit(0);
}

const jobId = args[1];
if (!jobId) {
  console.error(`Missing jobId for ${action}`);
  process.exit(1);
}

const job = data.jobs.find((item) => item.id === jobId);
if (!job) {
  const nativeResult = runNativeBridge(action, jobId);
  if (!nativeResult.success) {
    console.error(nativeResult.error || `Job not found: ${jobId}`);
    process.exit(1);
  }
  console.log(JSON.stringify(nativeResult.job, null, 2));
  process.exit(0);
}

if (action === 'cancel') {
  job.status = 'cancelled';
  job.enabled = false;
} else if (action === 'disable') {
  job.enabled = false;
} else if (action === 'enable') {
  job.enabled = true;
  if (job.status === 'cancelled') job.status = 'scheduled';
}

job.updatedAt = nowIso();
data.lastUpdated = nowIso();
writeJson(scheduleFile, data);
console.log(JSON.stringify(job, null, 2));
