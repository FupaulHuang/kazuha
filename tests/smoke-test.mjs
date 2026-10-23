import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { inflateSync } from 'node:zlib';

// Exercises the published Windows executable through its own documented MCP bridge.
// All projects, exports and temporary settings belong to this workspace.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const exe = process.env.COMPOSA_TEST_EXE || path.join(root, 'dist/portable/composa-1.4.0-win-x64/composa.exe');
const out = path.join(root, 'verification');
const samples = path.join(root, 'samples');
fs.mkdirSync(out, { recursive: true });
fs.mkdirSync(samples, { recursive: true });
const profile = path.join(out, 'test-profile');
const appdata = path.join(profile, 'Roaming');
const localdata = path.join(profile, 'Local');
fs.mkdirSync(path.join(appdata, 'Composa'), { recursive: true });
fs.mkdirSync(localdata, { recursive: true });
fs.writeFileSync(path.join(appdata, 'Composa/settings.json'), JSON.stringify({ AllowAiControl: true, CheckForUpdates: false, WindowWidth: 1400, WindowHeight: 940 }, null, 2));
const pipe = process.env.COMPOSA_MCP_PIPE || `composa-smoke-${process.pid}`;
const env = { ...process.env, COMPOSA_MCP_PIPE: pipe, COMPOSA_DISABLE_UPDATE_CHECK: '1', APPDATA: appdata, LOCALAPPDATA: localdata };
const report = { started: new Date().toISOString(), executable: exe, pipe, checks: [], calls: [] };
const log = fs.createWriteStream(path.join(out, 'smoke-runtime.log'));
let app, bridge;
let sequence = 0;
const pending = new Map();
function record(name, detail) { report.checks.push({ name, passed: true, detail }); console.log(`PASS ${name}`); }
function rpc(method, params = {}, timeout = 30000) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timed out: ${method}`)); }, timeout);
    pending.set(id, { resolve, reject, timer });
    bridge.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
async function call(name, args = {}) {
  const response = await rpc('tools/call', { name, arguments: args });
  const text = response.content?.filter(c => c.type === 'text').map(c => c.text).join('\n') || '';
  report.calls.push({ name, arguments: args, text, isError: !!response.isError });
  if (response.isError) throw new Error(`${name}: ${text}`);
  return { text, response };
}
async function namedShape(name, args) {
  const result = await call('add_shape', args);
  const original = result.text.match(/"([^"]+)"/)?.[1];
  assert.ok(original, result.text);
  await call('set_layer', { layer: original, name });
}
function png(file) {
  const bytes = fs.readFileSync(file);
  assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  let width, height, channels, bitDepth, interlace;
  const idat = [];
  for (let offset = 8; offset < bytes.length;) {
    const len = bytes.readUInt32BE(offset);
    const kind = bytes.toString('ascii', offset + 4, offset + 8);
    const data = bytes.subarray(offset + 8, offset + 8 + len);
    if (kind === 'IHDR') {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4); bitDepth = data[8];
      channels = { 2: 3, 6: 4 }[data[9]]; interlace = data[12];
    }
    if (kind === 'IDAT') idat.push(data);
    offset += len + 12;
    if (kind === 'IEND') break;
  }
  assert.equal(bitDepth, 8); assert.equal(interlace, 0); assert.ok(channels);
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels, pixels = Buffer.alloc(width * height * 4);
  let previous = Buffer.alloc(stride), pos = 0;
  function paeth(a, b, c) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); return pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
  for (let y = 0; y < height; y++) {
    const filter = raw[pos++], row = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? row[x - channels] : 0, b = previous[x], c = x >= channels ? previous[x - channels] : 0;
      const predictors = [0, a, b, Math.floor((a + b) / 2), paeth(a, b, c)];
      assert.ok(filter >= 0 && filter <= 4);
      row[x] = (raw[pos++] + predictors[filter]) & 255;
    }
    for (let x = 0; x < width; x++) {
      const p = (y * width + x) * 4;
      row.copy(pixels, p, x * channels, x * channels + 3);
      pixels[p + 3] = channels === 4 ? row[x * channels + 3] : 255;
    }
    previous = row;
  }
  return { width, height, hash: createHash('sha256').update(pixels).digest('hex'), at: (x, y) => [...pixels.subarray((y * width + x) * 4, (y * width + x + 1) * 4)] };
}
try {
  assert.ok(fs.existsSync(exe), `Missing executable: ${exe}`);
  if (!process.argv.includes('--attach')) {
    app = spawn(exe, [], { cwd: path.dirname(exe), env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    app.stdout.pipe(log, { end: false }); app.stderr.pipe(log, { end: false });
    app.on('error', error => log.write(`Application launch: ${error.stack}\n`));
    app.on('exit', (code, signal) => { report.appExit = { code, signal }; if (!log.writableEnded) log.write(`Application exit: ${code}, ${signal}\n`); });
    report.appPid = app.pid;
  }
  bridge = spawn(exe, ['--mcp'], { cwd: path.dirname(exe), env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  bridge.stderr.pipe(log, { end: false });
  bridge.on('error', error => { for (const item of pending.values()) item.reject(error); });
  readline.createInterface({ input: bridge.stdout }).on('line', line => {
    try {
      const message = JSON.parse(line), item = pending.get(message.id);
      if (!item) return;
      clearTimeout(item.timer); pending.delete(message.id);
      if (message.error) item.reject(new Error(JSON.stringify(message.error))); else item.resolve(message.result);
    } catch (error) { log.write(`Protocol: ${error.message}: ${line}\n`); }
  });
  const initialized = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'workspace-smoke-test', version: '1.0' } });
  report.server = initialized.serverInfo;
  bridge.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  let tools = [];
  for (let i = 0; i < 40; i++) {
    tools = (await rpc('tools/list')).tools || [];
    if (tools.length) break;
    if (i === 2) console.log(`WAITING_FOR_MCP appPid=${app?.pid || 'external'} pipe=${pipe}`);
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  assert.ok(tools.length, 'No tools: Help > Allow AI Control is off, or redirected APPDATA was not used.');
  fs.writeFileSync(path.join(out, 'mcp-tools.json'), JSON.stringify(tools, null, 2));
  record('Published app and MCP bridge start', `${tools.length} tools; ${initialized.serverInfo?.version}`);

  await call('new_document', { width: 320, height: 240, background: '#16232C' });
  await namedShape('Orange rectangle', { kind: 'rectangle', x: 40, y: 30, width: 120, height: 80, color: '#F6753D' });
  const sampled = await call('sample_color', { points: [[60.5, 50.5]], radius: 0.5 });
  assert.match(sampled.text, /#F6753D/);
  record('Layer compositing and color', sampled.text);
  await call('set_layer', { layer: 'Orange rectangle', opacity: 0.5 });
  const half = await call('sample_color', { points: [[60.5, 50.5]], radius: 0.5 });
  assert.doesNotMatch(half.text, /#F6753D/);
  await call('undo');
  assert.match((await call('sample_color', { points: [[60.5, 50.5]], radius: 0.5 })).text, /#F6753D/);
  if (tools.some(tool => tool.name === 'redo')) {
    await call('redo');
    assert.equal((await call('sample_color', { points: [[60.5, 50.5]], radius: 0.5 })).text, half.text);
    await call('undo');
    record('Redo', 'Restored the exact opacity result');
  } else report.limitations = ['The published MCP API has no redo tool; redo requires a separate native UI check.'];
  record('Opacity and undo', `50% result ${half.text}; undo restored original pixel color`);
  await call('transform_layer', { layer: 'Orange rectangle', x: 55, y: 35 });
  await call('duplicate_layer', { layer: 'Orange rectangle' });
  await call('undo');
  await call('new_layer', { name: 'Brush test' });
  await call('paint_stroke', { points: [[30, 180], [80, 180], [130, 180]], size: 12, color: '#62CBB2', hardness: 1 });
  assert.match((await call('sample_color', { points: [[80.5, 180.5]], radius: 0.5 })).text, /#62CBB2/);
  await call('add_text', { text: 'Windows layers', x: 28, y: 120, size: 22, font: 'Segoe UI', color: '#FFFFFF', bold: true });
  const description = (await call('describe_document')).text;
  assert.match(description, /text "Windows layers"/); assert.match(description, /Orange rectangle/); assert.match(description, /Brush test/);
  record('Transform, duplication, painting and editable text', description);
  const project = path.join(out, 'smoke.cmps'), exported = path.join(out, 'smoke.png');
  await call('save_document', { path: project, overwrite: true });
  await call('export_image', { path: exported, overwrite: true });
  const before = png(exported); assert.equal(before.width, 320); assert.equal(before.height, 240);
  assert.deepEqual(before.at(0, 0), [22, 35, 44, 255]);
  assert.deepEqual(before.at(70, 50), [246, 117, 61, 255]);
  const copy = path.join(out, 'smoke-reopened.cmps'); fs.copyFileSync(project, copy);
  await call('open_document', { path: copy });
  const reopened = (await call('describe_document')).text; assert.match(reopened, /text "Windows layers"/);
  const second = path.join(out, 'smoke-reopened.png'); await call('export_image', { path: second, overwrite: true });
  assert.equal(png(second).hash, before.hash);
  record('Save and reopen project with pixel-exact PNG export', { dimensions: [320, 240], pixelSha256: before.hash });

  await call('new_document', { width: 1400, height: 900, background: '#172822' });
  await namedShape('Sun', { kind: 'ellipse', x: 820, y: 170, width: 460, height: 460, color: '#EB7448' });
  await namedShape('Sun cutout', { kind: 'ellipse', x: 930, y: 190, width: 350, height: 350, color: '#172822' });
  await namedShape('Golden disc', { kind: 'ellipse', x: 930, y: 430, width: 250, height: 250, color: '#DDB86A' });
  await namedShape('Foreground panel', { kind: 'rectangle', x: 695, y: 550, width: 340, height: 190, color: '#EEE5CF' });
  await call('transform_layer', { layer: 'Foreground panel', rotation: -13 });
  await call('set_layer', { layer: 'Foreground panel', opacity: 0.9 });
  await call('add_line', { x1: 94, y1: 130, x2: 1306, y2: 130, width: 1, color: '#687B6B' });
  await call('add_line', { x1: 94, y1: 784, x2: 1306, y2: 784, width: 1, color: '#687B6B' });
  for (const item of [
    { text: 'COMPOSA  /  WINDOWS', x: 94, y: 76, size: 20, color: '#DDB86A' },
    { text: 'A study in layers', x: 1020, y: 78, size: 18, color: '#EEE5CF' },
    { text: 'MAKE', x: 86, y: 220, size: 128, color: '#EEE5CF', bold: true },
    { text: 'SPACE.', x: 86, y: 350, size: 128, color: '#EEE5CF', bold: true },
    { text: 'Ideas take shape.\nMake every layer your own.', x: 96, y: 560, size: 27, color: '#ABB6A3' },
    { text: '01  /  EDITABLE LAYERS', x: 96, y: 820, size: 18, color: '#DDB86A' },
    { text: 'Shapes  /  Type  /  Color', x: 1040, y: 820, size: 18, color: '#ABB6A3' }
  ]) await call('add_text', { font: 'Segoe UI', ...item });
  const demoProject = path.join(samples, 'Make Space.cmps');
  const demoExport = path.join(samples, 'Make Space.png');
  await call('save_document', { path: demoProject, overwrite: true });
  await call('export_image', { path: demoExport, overwrite: true });
  const demo = png(demoExport); assert.equal(demo.width, 1400); assert.equal(demo.height, 900);
  record('Editable demonstration project', { project: demoProject, export: demoExport, dimensions: [demo.width, demo.height] });
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack; console.error(error.stack); process.exitCode = 1;
} finally {
  report.finished = new Date().toISOString();
  fs.writeFileSync(path.join(out, 'smoke-results.json'), JSON.stringify(report, null, 2));
  bridge?.stdin.end();
  setTimeout(() => bridge?.kill(), 1000).unref();
  if (!process.argv.includes('--keep-open')) app?.kill();
  else { app?.stdout?.unpipe(log); app?.stderr?.unpipe(log); app?.stdout?.destroy(); app?.stderr?.destroy(); app?.unref(); }
  log.end();
  console.log(`Results: ${path.join(out, 'smoke-results.json')}`);
}
