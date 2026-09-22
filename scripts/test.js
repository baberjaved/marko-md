#!/usr/bin/env node
// Smoke tests for the CLI, hooks and live server. No dependencies. `npm test`
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { spawn, spawnSync } = require('child_process');

const root = path.join(__dirname, '..');
const bin = path.join(root, 'bin', 'marko.js');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'marko-test-'));
const home = path.join(tmp, 'home');
const env = Object.assign({}, process.env, { MARKO_HOME: home, MARKO_QUIET: '' });
let failures = 0;
const ok = (cond, msg) => { console.log(`${cond ? '  ✓' : '  ✗'} ${msg}`); if (!cond) failures++; };
const run = (args, opts) => spawnSync('node', [bin, ...args], Object.assign({ cwd: tmp, env, encoding: 'utf8' }, opts || {}));

// fixture project
fs.mkdirSync(path.join(tmp, 'plans'), { recursive: true });
const plan = path.join(tmp, 'plans', 'auth.md');
fs.writeFileSync(plan, '---\ntitle: Auth plan\n---\n# Auth plan\n\n## Phase 1\n- [ ] one\n- [x] two\n\n```js\nconst s = "</script>";\n```\n');
fs.writeFileSync(path.join(tmp, 'notes.md'), '# Notes\n\nplain notes\n');

console.log('marko open');
let r = run(['open', 'plans/auth.md', '--no-browser']);
ok(r.status === 0, `exits 0 (${(r.stderr || '').trim()})`);
const cached = fs.readdirSync(path.join(home, 'cache')).filter(f => f.endsWith('.html'));
ok(cached.length === 1, 'writes one cached page');
const page = fs.readFileSync(path.join(home, 'cache', cached[0]), 'utf8');
ok(page.includes('data-name="auth.md"') && page.includes('data-mode="plan"'), 'embeds name and plan mode (from modeByGlob)');
ok(page.includes('- [ ] one') && page.includes('<\\/script>') && !page.includes('"</script>"'), 'embeds the document and escapes </script>');
ok(/<title>Marko MD Viewer<\/title>/.test(page), 'is the viewer');
r = run(['open', 'notes.md', '--no-browser', '--mode', 'interactive']);
ok(/data-mode="interactive"/.test(fs.readFileSync(path.join(home, 'cache', fs.readdirSync(path.join(home, 'cache')).find(f => f.startsWith('notes'))), 'utf8')), '--mode overrides');

console.log('marko hook post-tool-use (no server)');
const hookIn = JSON.stringify({ session_id: 's1', cwd: tmp, hook_event_name: 'PostToolUse', tool_name: 'Write', tool_input: { file_path: plan } });
r = run(['hook', 'post-tool-use'], { input: hookIn });
ok(r.status === 0, 'exits 0');
let out = {}; try { out = JSON.parse(r.stdout); } catch (e) { /* */ }
ok(out.systemMessage && out.systemMessage.includes('plans/auth.md'), `mentions the file: ${out.systemMessage || r.stdout}`);
r = run(['hook', 'post-tool-use'], { input: JSON.stringify({ session_id: 's1', cwd: tmp, tool_name: 'Write', tool_input: { file_path: path.join(tmp, 'app.js') } }) });
ok(r.stdout === '', 'silent for non-Markdown');
r = run(['hook', 'post-tool-use'], { input: JSON.stringify({ session_id: 's1', cwd: tmp, tool_name: 'Write', tool_input: { file_path: path.join(tmp, 'notes.md') } }) });
ok(r.stdout === '', 'silent for Markdown outside the watch list (still recorded)');
const recent = JSON.parse(fs.readFileSync(path.join(home, 'recent.json'), 'utf8')).files;
ok(recent.length === 2 && recent[0].rel === 'notes.md', 'recent.json records both, newest first');
r = run(['recent']);
ok(r.stdout.includes('plans/auth.md'), 'marko recent lists it');

console.log('marko hook stop');
r = run(['hook', 'stop'], { input: JSON.stringify({ session_id: 's1', cwd: tmp, hook_event_name: 'Stop' }) });
out = {}; try { out = JSON.parse(r.stdout); } catch (e) { /* */ }
ok(out.systemMessage && out.systemMessage.includes('plans/auth.md') && !out.systemMessage.includes('notes.md'), 'lists watched files written this session');
r = run(['hook', 'stop'], { input: JSON.stringify({ session_id: 's1', cwd: tmp, hook_event_name: 'Stop' }) });
ok(r.stdout === '', 'nothing new → silent');

console.log('marko serve');
(async () => {
  const srv = spawn('node', [bin, 'serve', '--no-browser', '--port', '7451'], { cwd: tmp, env });
  let banner = ''; srv.stdout.on('data', d => { banner += d; });
  await new Promise(res => { const t = setInterval(() => { if (banner.includes('live at')) { clearInterval(t); res(); } }, 50); setTimeout(() => { clearInterval(t); res(); }, 4000); });
  const port = +((banner.match(/127\.0\.0\.1:(\d+)/) || [])[1] || 0);
  ok(port > 0, `started on port ${port}`);
  const get = p => new Promise(res => http.get({ host: '127.0.0.1', port, path: p }, r => { let b = ''; r.on('data', c => { b += c; }); r.on('end', () => res({ status: r.statusCode, body: b })); }).on('error', () => res({ status: 0, body: '' })));
  let g = await get('/'); ok(g.status === 200 && g.body.includes('data-live="1"'), 'serves the viewer in live mode');
  g = await get('/f/plans/auth.md'); ok(g.status === 200 && g.body.includes('# Auth plan'), 'serves a Markdown file by relative path');
  g = await get('/f/' + encodeURIComponent(plan)); ok(g.status === 200, 'serves a Markdown file by absolute path');
  g = await get('/f/../../etc/passwd'); ok(g.status === 404, 'refuses non-Markdown paths');
  g = await get('/f/plans/nope.md'); ok(g.status === 404, '404 for missing files');
  // SSE: expect an open-file event from the hook, then a change event on edit
  const events = [];
  const es = http.get({ host: '127.0.0.1', port, path: '/events' }, r => r.on('data', c => { events.push(String(c)); }));
  await new Promise(r => setTimeout(r, 200));
  r = run(['hook', 'post-tool-use'], { input: hookIn });
  out = {}; try { out = JSON.parse(r.stdout); } catch (e) { /* */ }
  ok(out.systemMessage && out.systemMessage.includes('live at'), 'hook reports the live URL when the server runs');
  await new Promise(r => setTimeout(r, 300));
  ok(events.join('').includes('event: open-file'), 'hook triggers an open-file event');
  fs.appendFileSync(plan, '- [ ] three\n');
  await new Promise(r => setTimeout(r, 1200));
  ok(events.join('').includes('event: change'), 'editing the file triggers a change event');
  es.destroy(); srv.kill('SIGINT');
  await new Promise(r => setTimeout(r, 300));
  ok(!fs.existsSync(path.join(home, 'server.json')), 'server.json removed on exit');
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(failures ? `\n${failures} failure(s)` : '\nall good');
  process.exit(failures ? 1 : 0);
})();
