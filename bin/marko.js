#!/usr/bin/env node
/*
 * marko — open Markdown written by Claude in the Marko viewer.
 * Zero dependencies. Node 18+.
 *
 *   marko open <file> [--mode reading|plan|interactive] [--browser] [--no-browser]
 *   marko serve [file] [--port 7331] [--no-browser]
 *   marko recent [-n 10]
 *   marko hook post-tool-use | stop        (called by Claude Code hooks; reads JSON on stdin)
 *   marko path                             (prints the viewer's location)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');
const crypto = require('crypto');
const { spawn } = require('child_process');

const VERSION = require('../package.json').version;
const ROOT = path.join(__dirname, '..');
const VIEWER = process.env.MARKO_VIEWER || path.join(ROOT, 'viewer', 'marko.html');
const DATA = process.env.MARKO_HOME || path.join(os.homedir(), '.marko');
const MD_EXT = /\.(md|markdown|mdx|mdown|txt)$/i;
const MODES = ['reading', 'plan', 'interactive'];

const DEFAULTS = {
  watch: ['plans/**', 'docs/**', '**/*plan*.md', '**/*roadmap*.md', '**/*checklist*.md', '**/*spec*.md', '**/*report*.md', '**/*summary*.md', '**/*.PLAN.md'],
  ignore: ['node_modules/**', '.git/**', '**/CLAUDE.md', '**/CHANGELOG.md', '**/LICENSE.md'],
  autoOpen: 'server',   // true = open a browser tab on every matching write; "server" = only refresh a running `marko serve`; false = hint only
  port: 7331,
  modeByGlob: { 'plans/**': 'plan', '**/*plan*.md': 'plan', '**/*roadmap*.md': 'plan', '**/*checklist*.md': 'plan', 'docs/**': 'reading', '**/*report*.md': 'reading' },
};

/* ---------- small utilities ---------- */
function ensureDir(p) { fs.mkdirSync(p, { recursive: true }); return p; }
function readJSON(p, fallback) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return fallback; } }
function writeJSON(p, obj) { ensureDir(path.dirname(p)); fs.writeFileSync(p, JSON.stringify(obj, null, 2)); }
function toPosix(p) { return p.split(path.sep).join('/'); }
function escAttr(s) { return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); }
function sha(s) { return crypto.createHash('sha1').update(s).digest('hex').slice(0, 12); }
function log(...a) { if (!process.env.MARKO_QUIET) console.log(...a); }

function loadConfig(cwd) {
  const user = readJSON(path.join(DATA, 'config.json'), {});
  const project = readJSON(path.join(cwd, '.claude', 'marko.json'), {});
  const cfg = Object.assign({}, DEFAULTS, user, project);
  cfg.modeByGlob = Object.assign({}, DEFAULTS.modeByGlob, user.modeByGlob || {}, project.modeByGlob || {});
  return cfg;
}

// glob → regex: ** (any path), * (segment), ? (char). Patterns without "/" match the basename anywhere.
function globToRegex(glob) {
  let g = glob.replace(/\\/g, '/');
  const anywhere = !g.includes('/');
  let re = '';
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === '*') {
      if (g[i + 1] === '*') { i++; if (i === g.length - 1) re += '.*'; else { if (g[i + 1] === '/') i++; re += '(?:.*/)?'; } }
      else re += '[^/]*';
    }
    else if (c === '?') re += '[^/]';
    else if ('.+^$()[]{}|\\'.includes(c)) re += '\\' + c;
    else re += c;
  }
  return new RegExp((anywhere ? '(^|/)' : '^') + re + '$', 'i');
}
function matchAny(rel, globs) { rel = toPosix(rel); return (globs || []).some(g => globToRegex(g).test(rel)); }
function modeFor(rel, cfg, explicit) {
  if (explicit && MODES.includes(explicit)) return explicit;
  for (const [g, m] of Object.entries(cfg.modeByGlob || {})) if (matchAny(rel, [g]) && MODES.includes(m)) return m;
  return '';
}

function markoApp() {
  if (process.platform !== 'darwin') return null;
  for (const p of ['/Applications/Marko.app', path.join(os.homedir(), 'Applications', 'Marko.app')]) if (fs.existsSync(p)) return p;
  return null;
}
function openInBrowser(target) {
  const p = process.platform;
  const [cmd, args] = p === 'darwin' ? ['open', [target]] : p === 'win32' ? ['cmd', ['/c', 'start', '', target]] : ['xdg-open', [target]];
  try { const child = spawn(cmd, args, { detached: true, stdio: 'ignore' }); child.on('error', () => {}); child.unref(); return true; } catch (e) { return false; }
}

function serverInfo() {
  const info = readJSON(path.join(DATA, 'server.json'), null);
  if (!info || !info.pid) return null;
  try { process.kill(info.pid, 0); return info; } catch (e) { return null; }
}
function notifyServer(info, payload) {
  return new Promise(resolve => {
    const body = JSON.stringify(payload);
    const req = http.request({ host: '127.0.0.1', port: info.port, path: '/notify', method: 'POST', headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) }, timeout: 800 }, res => { res.resume(); resolve(res.statusCode === 200); });
    req.on('error', () => resolve(false)); req.on('timeout', () => { req.destroy(); resolve(false); });
    req.end(body);
  });
}

/* ---------- open ---------- */
function buildPage(md, name, mode, extraAttrs) {
  const viewer = fs.readFileSync(VIEWER, 'utf8');
  const island = `<script type="text/markdown" id="doc" data-name="${escAttr(name)}" data-mode="${escAttr(mode || '')}"${extraAttrs || ''}>\n${md.replace(/<\/(script)/gi, '<\\/$1')}\n</script>`;
  const re = /<script type="text\/markdown" id="doc"[^>]*><\/script>/;
  if (!re.test(viewer)) throw new Error('viewer template is missing the #doc island');
  return viewer.replace(re, () => island);
}
async function cmdOpen(args) {
  const file = args._[0];
  if (!file) fail('usage: marko open <file.md> [--mode reading|plan|interactive] [--no-browser]');
  const abs = path.resolve(file);
  if (!fs.existsSync(abs)) fail(`no such file: ${file}`);
  const cwd = process.cwd(), cfg = loadConfig(cwd);
  const rel = toPosix(path.relative(cwd, abs));
  const mode = modeFor(rel, cfg, args.mode);
  const srv = serverInfo();
  let target;
  const app = !args.browser && !args.static && cfg.app !== false && markoApp();
  if (app && !srv) {
    // Marko.app is installed: open the file natively (it watches the file for changes itself).
    if (!args['no-browser']) { const child = spawn('open', ['-a', app, abs], { detached: true, stdio: 'ignore' }); child.on('error', () => {}); child.unref(); }
    log(`Opened ${rel || abs} in Marko.app${mode ? ` (${mode} mode)` : ''}`);
    return abs;
  }
  if (srv && !args.static) {
    // A live server is running: use it so the tab refreshes when the file changes.
    const ok = await notifyServer(srv, { file: abs, mode });
    target = `http://127.0.0.1:${srv.port}/?f=${encodeURIComponent(abs)}${mode ? '&mode=' + mode : ''}`;
    if (ok) log(`Live: ${target}`);
  } else {
    const md = fs.readFileSync(abs, 'utf8');
    const out = path.join(ensureDir(path.join(DATA, 'cache')), `${path.basename(abs, path.extname(abs))}-${sha(abs)}.html`);
    fs.writeFileSync(out, buildPage(md, path.basename(abs), mode));
    target = out;
    log(`Wrote ${out}`);
  }
  if (!args['no-browser']) openInBrowser(target);
  log(`Opened ${rel || abs}${mode ? ` in ${mode[0].toUpperCase() + mode.slice(1)} mode` : ''}`);
  return target;
}

/* ---------- serve ---------- */
function cmdServe(args) {
  const cwd = process.cwd(), cfg = loadConfig(cwd);
  const port0 = +(args.port || cfg.port || 7331);
  const initial = args._[0] ? path.resolve(args._[0]) : '';
  if (initial && !fs.existsSync(initial)) fail(`no such file: ${args._[0]}`);
  const clients = new Set(); const watched = new Map(); const watchedFiles = new Set();

  function broadcast(event, data) { const msg = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`; for (const res of clients) res.write(msg); }
  function resolveFile(spec) {
    // /f/<absolute or cwd-relative path>. Only Markdown-ish files, only existing ones.
    const p = path.isAbsolute(spec) ? spec : path.resolve(cwd, spec);
    if (!MD_EXT.test(p)) return null;
    try { return fs.statSync(p).isFile() ? p : null; } catch (e) { return null; }
  }
  function watch(abs) {
    // Watch the directory rather than the file: editors that save by rename would otherwise detach a file watcher.
    watchedFiles.add(abs);
    const dir = path.dirname(abs);
    if (watched.has(dir)) return;
    const timers = new Map();
    const changed = file => { clearTimeout(timers.get(file)); timers.set(file, setTimeout(() => broadcast('change', { file }), 150)); };
    const onEvent = (evt, filename) => {
      if (filename) { const f = path.join(dir, String(filename)); if (watchedFiles.has(f)) changed(f); }
      else for (const f of watchedFiles) if (path.dirname(f) === dir) changed(f);
    };
    try { const w = fs.watch(dir, onEvent); w.on('error', () => {}); watched.set(dir, w); }
    catch (e) { fs.watchFile(abs, { interval: 700 }, () => changed(abs)); watched.set(dir, { close: () => fs.unwatchFile(abs) }); }
  }

  const viewer = fs.readFileSync(VIEWER, 'utf8').replace(/<script type="text\/markdown" id="doc"([^>]*)><\/script>/, (m, attrs) => `<script type="text/markdown" id="doc"${attrs} data-live="1"></script>`);
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (req.method === 'GET' && url.pathname === '/') { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }); return res.end(viewer); }
    if (req.method === 'GET' && url.pathname.startsWith('/f/')) {
      const abs = resolveFile(decodeURIComponent(url.pathname.slice(3)));
      if (!abs) { res.writeHead(404); return res.end('not found'); }
      watch(abs);
      res.writeHead(200, { 'content-type': 'text/markdown; charset=utf-8', 'cache-control': 'no-store', 'x-marko-file': encodeURI(abs), 'x-marko-mode': modeFor(path.relative(cwd, abs), cfg) });
      return fs.createReadStream(abs).pipe(res);
    }
    if (req.method === 'GET' && url.pathname === '/events') {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
      res.write(': connected\n\n'); clients.add(res);
      const ping = setInterval(() => res.write(': ping\n\n'), 25000);
      req.on('close', () => { clearInterval(ping); clients.delete(res); });
      return;
    }
    if (req.method === 'POST' && url.pathname === '/notify') {
      let body = ''; req.on('data', c => { body += c; if (body.length > 1e6) req.destroy(); });
      req.on('end', () => {
        let d = {}; try { d = JSON.parse(body || '{}'); } catch (e) { /* ignore */ }
        const abs = d.file && resolveFile(d.file);
        if (!abs) { res.writeHead(400); return res.end('bad file'); }
        watch(abs); broadcast('open-file', { file: abs, mode: d.mode || '' });
        res.writeHead(200); res.end('ok');
      });
      return;
    }
    if (req.method === 'GET' && url.pathname === '/recent') { res.writeHead(200, { 'content-type': 'application/json' }); return res.end(JSON.stringify(recentList())); }
    res.writeHead(404); res.end('not found');
  });

  const tryListen = (port, attempts) => server.listen(port, '127.0.0.1').once('error', err => {
    if (err.code === 'EADDRINUSE' && attempts > 0) { server.removeAllListeners('error'); tryListen(port + 1, attempts - 1); } else fail(`could not start server: ${err.message}`);
  });
  server.on('listening', () => {
    const port = server.address().port;
    writeJSON(path.join(DATA, 'server.json'), { pid: process.pid, port, root: cwd, started: Date.now() });
    const url = `http://127.0.0.1:${port}/` + (initial ? `?f=${encodeURIComponent(initial)}${modeFor(path.relative(cwd, initial), cfg, args.mode) ? '&mode=' + modeFor(path.relative(cwd, initial), cfg, args.mode) : ''}` : '');
    log(`Marko is live at ${url}`);
    log(initial ? `Watching ${path.relative(cwd, initial)}` : 'Waiting for Markdown — files Claude writes will open here. Press Ctrl+C to stop.');
    if (!args['no-browser']) openInBrowser(url);
  });
  const stop = () => { try { fs.unlinkSync(path.join(DATA, 'server.json')); } catch (e) { /* ignore */ } for (const w of watched.values()) { try { w.close(); } catch (e) { /* ignore */ } } server.close(); process.exit(0); };
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
  tryListen(port0, 5);
}

/* ---------- recent ---------- */
const RECENT = path.join(DATA, 'recent.json');
function recentList() { return (readJSON(RECENT, { files: [] }).files || []).slice().sort((a, b) => b.t - a.t); }
function recordRecent(entry) {
  const db = readJSON(RECENT, { files: [] });
  db.files = (db.files || []).filter(f => f.file !== entry.file);
  db.files.unshift(entry); db.files = db.files.slice(0, 100);
  writeJSON(RECENT, db);
}
function cmdRecent(args) {
  const n = +(args.n || 10); const list = recentList().slice(0, n);
  if (!list.length) return log('No Markdown files recorded yet. Files Claude writes are recorded by the PostToolUse hook.');
  for (const f of list) log(`${new Date(f.t).toLocaleString()}  ${f.rel || f.file}`);
}

/* ---------- hooks (Claude Code) ---------- */
function readStdinJSON() {
  return new Promise(resolve => {
    let data = ''; process.stdin.setEncoding('utf8');
    process.stdin.on('data', c => { data += c; }); process.stdin.on('end', () => { try { resolve(JSON.parse(data || '{}')); } catch (e) { resolve({}); } });
    setTimeout(() => resolve({}), 1500).unref();
  });
}
async function cmdHook(args) {
  const which = args._[0];
  const input = await readStdinJSON();
  const cwd = input.cwd || process.cwd();
  const cfg = loadConfig(cwd);
  if (which === 'post-tool-use') {
    const fp = input.tool_input && input.tool_input.file_path;
    if (!fp || !MD_EXT.test(fp)) return; // fast path: not Markdown
    const abs = path.resolve(cwd, fp); const rel = toPosix(path.relative(cwd, abs));
    if (matchAny(rel, cfg.ignore)) return;
    const matched = !cfg.watch || !cfg.watch.length || matchAny(rel, cfg.watch);
    recordRecent({ file: abs, rel, session_id: input.session_id || '', t: Date.now(), matched });
    if (!matched) return;
    const mode = modeFor(rel, cfg);
    const srv = serverInfo();
    let msg;
    if (srv && await notifyServer(srv, { file: abs, mode })) msg = `Marko: ${rel} is showing live at http://127.0.0.1:${srv.port}/`;
    else if (cfg.autoOpen === true) { await cmdOpen({ _: [abs], mode, 'no-browser': false }); msg = `Marko: opened ${rel} in the browser${mode ? ` (${mode} mode)` : ''}.`; }
    else msg = `Marko: ${rel} was written — the user can review it with /marko:view ${rel} (or \`marko open ${rel}\`).`;
    process.stdout.write(JSON.stringify({ systemMessage: msg, hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: msg } }));
    return;
  }
  if (which === 'stop') {
    const sid = input.session_id || '';
    const marks = readJSON(path.join(DATA, 'stop-marks.json'), {});
    const since = marks[sid] || 0;
    const files = recentList().filter(f => f.session_id === sid && f.t > since && f.matched);
    marks[sid] = Date.now(); writeJSON(path.join(DATA, 'stop-marks.json'), marks);
    if (!files.length) return;
    const srv = serverInfo();
    const list = files.slice(0, 6).map(f => f.rel).join(', ');
    const msg = srv ? `Marko: Markdown written this turn (${list}) is live at http://127.0.0.1:${srv.port}/.` : `Marko: Markdown written this turn — ${list}. Review with /marko:view <file> or \`marko open <file>\`.`;
    process.stdout.write(JSON.stringify({ systemMessage: msg }));
    return;
  }
  fail('usage: marko hook post-tool-use|stop');
}

/* ---------- arg parsing & dispatch ---------- */
function parseArgs(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) { const k = a.slice(2); const v = argv[i + 1]; if (v !== undefined && !v.startsWith('-') && ['mode', 'port', 'n'].includes(k)) { out[k] = v; i++; } else out[k] = true; }
    else if (a === '-n') { out.n = argv[++i]; }
    else out._.push(a);
  }
  return out;
}
function fail(msg) { console.error(msg); process.exit(1); }
function help() {
  log(`marko ${VERSION} — Markdown viewer for Claude output

  marko open <file> [--mode reading|plan|interactive] [--browser] [--no-browser]
                                                      opens in Marko.app when installed, else the browser
  marko serve [file] [--port 7331] [--no-browser]     live view: refreshes when the file changes
  marko recent [-n 10]                                Markdown files Claude wrote recently
  marko path                                          location of the viewer HTML
  marko hook post-tool-use|stop                       used by Claude Code hooks (JSON on stdin)

Config: .claude/marko.json in the project, ~/.marko/config.json for the user.
Docs:   https://github.com/baberjaved/marko-md`);
}
(async () => {
  const args = parseArgs(process.argv.slice(2));
  const cmd = args._.shift();
  if (args.version || cmd === 'version') return log(VERSION);
  if (!cmd || args.help || cmd === 'help') return help();
  if (cmd === 'open') return cmdOpen(args);
  if (cmd === 'serve') return cmdServe(args);
  if (cmd === 'recent') return cmdRecent(args);
  if (cmd === 'path') return log(VIEWER);
  if (cmd === 'hook') return cmdHook(args);
  if (MD_EXT.test(cmd)) { args._.unshift(cmd); return cmdOpen(args); } // `marko notes.md`
  fail(`unknown command: ${cmd}\n`);
})().catch(e => fail(e.message));
