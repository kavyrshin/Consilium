#!/usr/bin/env node
// Local read-only viewer for consilium cases. No npm dependencies on the server;
// markdown (and mermaid, when a document has diagrams) are rendered in the browser from
// pinned CDN builds checked with Subresource Integrity.
//
//   node reader.cjs <cases-dir> [--port N] [--lang en|ru] [--public]
//
// --public  for sharing through a tunnel such as ngrok: accepts any Host header but
//           requires HTTP Basic auth (user "consilium", password from CM_READER_PASSWORD
//           or generated at start and printed once).
//
// Normally started through scripts/reader.sh, which resolves <cases-dir> from the same
// configuration as the rest of the skill.
//
// Security, because documents are written by models that read arbitrary repositories and
// could have been prompt-injected into emitting HTML:
//   - listens on 127.0.0.1 only, never on the network;
//   - rejects requests whose Host header is not localhost (blocks DNS rebinding), unless
//     --public, where a password is required instead;
//   - serves only *.md files that really live under <cases-dir> (symlinks resolved);
//   - sanitizes rendered markdown with DOMPurify and sends a strict Content-Security-Policy
//     with a per-response nonce, so injected markup cannot run script or load remote images.

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ------------------------------------------------------------------ arguments

const args = process.argv.slice(2);
function option(name, fallback) {
  const i = args.indexOf(name);
  if (i === -1) return fallback;
  const value = args[i + 1];
  args.splice(i, 2);
  return value;
}
const PORT = parseInt(option('--port', process.env.CM_READER_PORT || '4600'), 10);
const LANG = option('--lang', process.env.CM_LANG || 'en') === 'ru' ? 'ru' : 'en';
const PUBLIC = args.includes('--public');
if (PUBLIC) args.splice(args.indexOf('--public'), 1);
const HOST = '127.0.0.1';
const USER = 'consilium';
const PASSWORD = PUBLIC ? (process.env.CM_READER_PASSWORD || crypto.randomBytes(12).toString('base64url')) : null;
if (PUBLIC && PASSWORD.length < 12) {
  console.error('consilium reader: CM_READER_PASSWORD must be at least 12 characters for --public');
  process.exit(2);
}
const EXPECTED_AUTH = PUBLIC ? 'Basic ' + Buffer.from(USER + ':' + PASSWORD).toString('base64') : null;

// Constant-time comparison, so the password cannot be guessed byte by byte from timing.
function authorized(header) {
  const a = Buffer.from(String(header || ''));
  const b = Buffer.from(EXPECTED_AUTH);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
if (!args[0]) {
  console.error('usage: reader.cjs <cases-dir> [--port N] [--lang en|ru]');
  process.exit(2);
}
fs.mkdirSync(args[0], { recursive: true });
const ROOT = fs.realpathSync(args[0]);

// Pinned front-end libraries. To update: change the version and recompute the hash
// (curl -s URL | openssl dgst -sha384 -binary | openssl base64 -A).
const LIBS = {
  marked: {
    src: 'https://cdn.jsdelivr.net/npm/marked@18.0.13/lib/marked.umd.js',
    sri: 'sha384-Jy8qDMspJASzATgFngF2ompIKy0StbCcvuTE65mxDm/E0/YSIF6Ndc+5V7bbwRcw',
  },
  purify: {
    src: 'https://cdn.jsdelivr.net/npm/dompurify@3.4.15/dist/purify.min.js',
    sri: 'sha384-uUMu9JDY09vBzRf9SPcK2VgUj+W/70J6Soc+Dded5P474ElQ63iv9j5N3DE7Kp3N',
  },
  // 5 MB: loaded only when a document actually contains a mermaid block.
  mermaid: {
    src: 'https://cdn.jsdelivr.net/npm/mermaid@12.0.0/dist/mermaid.min.js',
    sri: 'sha384-xzghz1GQ5u9HCpVskeDPqMsdogD1yvuMQbEK53+wi+G70+6J1AG0L2cfi9PHjDWI',
  },
};

const STRINGS = {
  en: {
    loading: 'Loading…', empty: 'No cases yet', loadFailed: 'Could not load the file.',
    collapse: 'Collapse / expand the panel', resize: 'Drag to resize the panel',
    hide: 'Hide this case from the list (files stay on disk)', hidden: 'Hidden cases',
    restore: 'restore', copyPath: 'Copy the local path of this file', live: 'Live',
    offline: 'Reconnecting…',
  },
  ru: {
    loading: 'Загрузка…', empty: 'Пока пусто', loadFailed: 'Не удалось загрузить файл.',
    collapse: 'Свернуть / развернуть панель', resize: 'Потяни, чтобы изменить ширину панели',
    hide: 'Скрыть кейс из списка (файлы на диске останутся)', hidden: 'Скрытые кейсы',
    restore: 'вернуть', copyPath: 'Скопировать локальный путь к файлу', live: 'Онлайн',
    offline: 'Переподключение…',
  },
}[LANG];

// ------------------------------------------------------------------ file tree

// Files inside a case follow the stages of the process, not the alphabet: brief, reviews,
// decision, then the implementation documents. Unknown files go last, alphabetically.
function fileRank(name) {
  const n = name.toLowerCase();
  if (n === 'brief.md') return 0;
  if (n.endsWith('-impl-review.md')) return 5;
  if (n.endsWith('-review.md')) return 1;
  if (n === 'decision.md') return 2;
  if (n === 'impl-report.md') return 4;
  if (n === 'fix-report.md') return 6;
  return 9;
}

function datePrefix(name) {
  const m = /^(\d{4}-\d{2}-\d{2})-/.exec(name);
  return m ? m[1] : null;
}

function walk(dir) {
  const dirs = [];
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    // Run artefacts (.logs, .runners, candidates) are hidden.
    if (entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const st = fs.statSync(full);
      dirs.push({ name: entry.name, path: path.relative(ROOT, full), ctime: st.birthtimeMs || st.mtimeMs, ...walk(full) });
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.md')) {
      files.push({ name: entry.name, path: path.relative(ROOT, full) });
    }
  }
  // Cases: newest date in the folder name first. The name, not the file-system time, is
  // authoritative (birth times do not always follow the logical order); the time only
  // breaks ties within one day.
  dirs.sort((a, b) => {
    const da = datePrefix(a.name);
    const db = datePrefix(b.name);
    if (da && db && da !== db) return db.localeCompare(da);
    return b.ctime - a.ctime;
  });
  files.sort((a, b) => fileRank(a.name) - fileRank(b.name) || a.name.localeCompare(b.name));
  return { dirs, files };
}

// Resolves a client path to a real file under ROOT, or null. Symlinks are resolved first,
// so a link inside the cases folder cannot expose a file outside it.
function safeResolve(rel) {
  if (typeof rel !== 'string' || !rel.toLowerCase().endsWith('.md') || rel.includes('\0')) return null;
  let real;
  try {
    real = fs.realpathSync(path.resolve(ROOT, rel));
  } catch (e) {
    return null;
  }
  if (!real.startsWith(ROOT + path.sep)) return null;
  if (!fs.statSync(real).isFile()) return null;
  return real;
}

// ------------------------------------------------------------------ page

function page(nonce) {
  return `<!doctype html>
<html lang="${LANG}">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Consilium reader</title>
<script src="${LIBS.marked.src}" integrity="${LIBS.marked.sri}" crossorigin="anonymous"></script>
<script src="${LIBS.purify.src}" integrity="${LIBS.purify.sri}" crossorigin="anonymous"></script>
<style>
  :root {
    --bg: #ffffff; --fg: #1f2328; --muted: #656d76; --border: #d1d9e0;
    --sidebar-bg: #f6f8fa; --link: #0969da; --code-bg: rgba(175,184,193,0.2);
    --active-bg: #ddf4ff; --banner-bg: #fff8c5;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0d1117; --fg: #e6edf3; --muted: #8b949e; --border: #30363d;
      --sidebar-bg: #161b22; --link: #4493f8; --code-bg: rgba(110,118,129,0.4);
      --active-bg: #10243e; --banner-bg: #3b2e00;
    }
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body { margin: 0; display: flex; background: var(--bg); color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
  #sidebar { width: 300px; min-width: 40px; flex-shrink: 0; overflow-y: auto; overflow-x: hidden;
    background: var(--sidebar-bg); border-right: 1px solid var(--border); padding: 16px 12px;
    display: flex; flex-direction: column; }
  #sidebar.collapsed { width: 40px !important; padding: 16px 8px; cursor: pointer; }
  #sidebar.collapsed #tree, #sidebar.collapsed #sidebar-header h1,
  #sidebar.collapsed #hidden-footer, #sidebar.collapsed #status { display: none; }
  #sidebar-header { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; }
  #collapse-btn { flex-shrink: 0; width: 24px; height: 24px; border: 1px solid var(--border);
    border-radius: 6px; background: var(--bg); color: var(--fg); cursor: pointer; font-size: 13px;
    line-height: 1; padding: 0; }
  #collapse-btn:hover { background: var(--code-bg); }
  #sidebar h1 { flex: 1; font-size: 14px; text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--muted); margin: 0; white-space: nowrap; }
  #status { font-size: 11px; color: var(--muted); white-space: nowrap; }
  #status::before { content: "●"; margin-right: 4px; color: #1a7f37; }
  #status.off::before { color: #9a6700; }
  #resize-handle { width: 5px; flex-shrink: 0; cursor: col-resize; }
  #resize-handle:hover, #resize-handle.dragging { background: var(--link); opacity: 0.5; }
  .folder { margin-bottom: 10px; }
  .folder-name { display: flex; align-items: center; gap: 6px; font-weight: 600; font-size: 13px;
    padding: 4px; word-break: break-word; cursor: pointer; user-select: none; border-radius: 6px; }
  .folder-name:hover { background: var(--code-bg); }
  .chevron { flex-shrink: 0; width: 10px; font-size: 10px; color: var(--muted); }
  .title { flex: 1; min-width: 0; }
  .hide-btn { flex-shrink: 0; visibility: hidden; border: none; background: none; cursor: pointer;
    color: var(--muted); font-size: 14px; line-height: 1; padding: 2px 4px; border-radius: 4px; }
  .folder-name:hover .hide-btn { visibility: visible; }
  .hide-btn:hover { background: var(--border); color: var(--fg); }
  #hidden-footer { margin-top: auto; padding-top: 12px; border-top: 1px solid var(--border);
    font-size: 12px; color: var(--muted); }
  #hidden-footer:empty { display: none; }
  #hidden-toggle { background: none; border: none; color: var(--muted); cursor: pointer;
    font-size: 12px; padding: 4px; text-align: left; width: 100%; border-radius: 6px; }
  #hidden-toggle:hover { background: var(--code-bg); color: var(--fg); }
  .hidden-row { display: flex; align-items: center; gap: 6px; padding: 3px 4px; word-break: break-word; }
  .restore-btn { flex-shrink: 0; border: none; background: none; cursor: pointer; color: var(--link);
    font-size: 12px; padding: 2px 4px; border-radius: 4px; }
  .restore-btn:hover { background: var(--code-bg); }
  .folder.collapsed .folder-body { display: none; }
  .folder-body { padding-left: 4px; }
  .file-link { display: flex; align-items: center; gap: 4px; padding: 4px 8px 4px 16px; font-size: 13px;
    color: var(--muted); text-decoration: none; border-radius: 6px; cursor: pointer; word-break: break-word; }
  .file-link:hover { background: var(--code-bg); color: var(--fg); }
  .file-link.active { background: var(--active-bg); color: var(--link); font-weight: 600; }
  .file-link.decision { color: var(--fg); font-weight: 600; }
  .copy-path-btn { flex-shrink: 0; border: none; background: none; cursor: pointer; opacity: 0.55;
    font-size: 12px; line-height: 1; padding: 2px 4px; border-radius: 4px; }
  .copy-path-btn:hover { opacity: 1; background: var(--border); }
  #content { flex: 1; min-width: 0; overflow-y: auto; padding: 40px 24px; }
  #doc { max-width: 860px; margin: 0 auto; line-height: 1.6; }
  #doc h1, #doc h2, #doc h3 { border-bottom: 1px solid var(--border); padding-bottom: 6px; }
  #doc a { color: var(--link); }
  #doc code { background: var(--code-bg); padding: 0.15em 0.35em; border-radius: 4px; font-size: 0.9em; }
  #doc pre { background: var(--code-bg); padding: 12px; border-radius: 8px; overflow-x: auto; }
  #doc pre code { background: none; padding: 0; }
  #doc table { border-collapse: collapse; width: 100%; margin: 12px 0; display: block; overflow-x: auto; }
  #doc th, #doc td { border: 1px solid var(--border); padding: 6px 10px; text-align: left; }
  #doc blockquote { margin: 0; padding: 0 1em; color: var(--muted); border-left: 4px solid var(--border); }
  #doc > blockquote:first-child { background: var(--banner-bg); color: var(--fg); padding: 8px 14px;
    border-left-color: #9a6700; border-radius: 6px; }
  #path { color: var(--muted); font-size: 12px; margin-bottom: 16px; word-break: break-all; }
  .empty { color: var(--muted); padding: 40px; }
  @media (max-width: 700px) {
    body { flex-direction: column; }
    #sidebar { width: 100% !important; max-height: 40vh; border-right: none; border-bottom: 1px solid var(--border); }
    #resize-handle { display: none; }
    #content { padding: 20px 16px; }
  }
</style>
</head>
<body>
  <nav id="sidebar">
    <div id="sidebar-header">
      <button id="collapse-btn"></button>
      <h1>Consilium</h1>
      <span id="status"></span>
    </div>
    <div id="tree"></div>
    <div id="hidden-footer"></div>
  </nav>
  <div id="resize-handle"></div>
  <main id="content"><div id="path"></div><div id="doc"></div></main>
<script nonce="${nonce}">
'use strict';
const T = ${JSON.stringify(STRINGS)};
const ROOT_ABS = ${JSON.stringify(PUBLIC ? '' : ROOT)};
const MERMAID = ${JSON.stringify(LIBS.mermaid)};
const NONCE = ${JSON.stringify(nonce)};

// Per-viewer UI state (panel width, collapsed and hidden cases). Storage can be blocked;
// the reader must work without it.
function load(key, fallback) { try { const v = localStorage.getItem(key); return v === null ? fallback : v; } catch (e) { return fallback; } }
function save(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }

const sidebar = document.getElementById('sidebar');
const collapseBtn = document.getElementById('collapse-btn');
const resizeHandle = document.getElementById('resize-handle');
const statusEl = document.getElementById('status');
collapseBtn.title = T.collapse;
resizeHandle.title = T.resize;
document.getElementById('tree').textContent = T.loading;

function setCollapsed(collapsed) {
  sidebar.classList.toggle('collapsed', collapsed);
  collapseBtn.textContent = collapsed ? '›' : '‹';
  save('consilium-sidebar-collapsed', collapsed ? '1' : '0');
}
setCollapsed(load('consilium-sidebar-collapsed', '0') === '1');
collapseBtn.onclick = function (e) { e.stopPropagation(); setCollapsed(!sidebar.classList.contains('collapsed')); };
sidebar.addEventListener('click', function () { if (sidebar.classList.contains('collapsed')) setCollapsed(false); });

const savedWidth = parseInt(load('consilium-sidebar-width', ''), 10);
if (savedWidth >= 180 && savedWidth <= 640) sidebar.style.width = savedWidth + 'px';
let resizing = false;
resizeHandle.addEventListener('mousedown', function (e) {
  if (sidebar.classList.contains('collapsed')) return;
  resizing = true; resizeHandle.classList.add('dragging'); document.body.style.userSelect = 'none'; e.preventDefault();
});
document.addEventListener('mousemove', function (e) {
  if (resizing) sidebar.style.width = Math.min(640, Math.max(180, e.clientX)) + 'px';
});
document.addEventListener('mouseup', function () {
  if (!resizing) return;
  resizing = false; resizeHandle.classList.remove('dragging'); document.body.style.userSelect = '';
  save('consilium-sidebar-width', parseInt(sidebar.style.width, 10));
});

function loadSet(key) { try { return new Set(JSON.parse(load(key, '[]'))); } catch (e) { return new Set(); } }
const collapsedFolders = loadSet('consilium-collapsed-folders');
const hiddenFolders = loadSet('consilium-hidden-folders');
function saveSet(key, set) { save(key, JSON.stringify(Array.from(set))); }
let showHidden = false;
let lastTree = null;
let currentPath = null;

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function markActive() {
  document.querySelectorAll('.file-link').forEach(function (a) { a.classList.toggle('active', a.dataset.path === currentPath); });
}

function renderTree(node, container, depth) {
  (node.dirs || []).forEach(function (d) {
    if (depth === 0 && hiddenFolders.has(d.path)) return;
    const wrap = el('div', 'folder');
    if (collapsedFolders.has(d.path)) wrap.classList.add('collapsed');
    const label = el('div', 'folder-name');
    const chevron = el('span', 'chevron', wrap.classList.contains('collapsed') ? '▸' : '▾');
    label.appendChild(chevron);
    label.appendChild(el('span', 'title', d.name));
    if (depth === 0) {
      const hideBtn = el('button', 'hide-btn', '×');
      hideBtn.title = T.hide;
      hideBtn.onclick = function (e) { e.stopPropagation(); hiddenFolders.add(d.path); saveSet('consilium-hidden-folders', hiddenFolders); rerenderTree(); };
      label.appendChild(hideBtn);
    }
    label.onclick = function () {
      const isCollapsed = wrap.classList.toggle('collapsed');
      chevron.textContent = isCollapsed ? '▸' : '▾';
      if (isCollapsed) collapsedFolders.add(d.path); else collapsedFolders.delete(d.path);
      saveSet('consilium-collapsed-folders', collapsedFolders);
    };
    wrap.appendChild(label);
    const body = el('div', 'folder-body');
    renderTree(d, body, depth + 1);
    wrap.appendChild(body);
    container.appendChild(wrap);
  });
  (node.files || []).forEach(function (f) {
    const isDecision = f.name.toLowerCase() === 'decision.md';
    const a = el('a', 'file-link' + (isDecision ? ' decision' : ''));
    a.dataset.path = f.path;
    a.onclick = function () { openFile(f.path); };
    a.appendChild(el('span', 'title', (isDecision ? '⚖️ ' : '') + f.name));
    if (isDecision && ROOT_ABS) {
      const copyBtn = el('button', 'copy-path-btn', '📋');
      copyBtn.title = T.copyPath;
      copyBtn.onclick = function (e) {
        e.preventDefault(); e.stopPropagation();
        navigator.clipboard.writeText(ROOT_ABS + '/' + f.path).then(
          function () { copyBtn.textContent = '✅'; setTimeout(function () { copyBtn.textContent = '📋'; }, 1200); },
          function () { copyBtn.textContent = '⚠️'; setTimeout(function () { copyBtn.textContent = '📋'; }, 1200); });
      };
      a.appendChild(copyBtn);
    }
    container.appendChild(a);
  });
}

function renderHiddenFooter() {
  const footer = document.getElementById('hidden-footer');
  footer.textContent = '';
  if (!hiddenFolders.size) return;
  const toggle = el('button', '', (showHidden ? '▾ ' : '▸ ') + T.hidden + ' (' + hiddenFolders.size + ')');
  toggle.id = 'hidden-toggle';
  toggle.onclick = function () { showHidden = !showHidden; renderHiddenFooter(); };
  footer.appendChild(toggle);
  if (!showHidden) return;
  Array.from(hiddenFolders).sort().reverse().forEach(function (p) {
    const row = el('div', 'hidden-row');
    row.appendChild(el('span', 'title', p));
    const restore = el('button', 'restore-btn', T.restore);
    restore.onclick = function () { hiddenFolders.delete(p); saveSet('consilium-hidden-folders', hiddenFolders); rerenderTree(); };
    row.appendChild(restore);
    footer.appendChild(row);
  });
}

function rerenderTree() {
  const container = document.getElementById('tree');
  container.textContent = '';
  if (!lastTree || (!lastTree.dirs.length && !lastTree.files.length)) {
    container.appendChild(el('div', 'empty', T.empty));
  } else {
    renderTree(lastTree, container, 0);
  }
  markActive();
  renderHiddenFooter();
}

// Mermaid is 5 MB, so it is fetched on first need, still pinned and integrity-checked.
let mermaidLoading = null;
function withMermaid() {
  if (window.mermaid) return Promise.resolve(window.mermaid);
  if (!mermaidLoading) {
    mermaidLoading = new Promise(function (resolve, reject) {
      const s = document.createElement('script');
      s.src = MERMAID.src; s.integrity = MERMAID.sri; s.crossOrigin = 'anonymous'; s.nonce = NONCE;
      s.onload = function () { window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' }); resolve(window.mermaid); };
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }
  return mermaidLoading;
}

function renderDoc(md) {
  const doc = document.getElementById('doc');
  // Documents are model-written: never insert unsanitized HTML.
  doc.innerHTML = DOMPurify.sanitize(marked.parse(md));
  const blocks = doc.querySelectorAll('pre code.language-mermaid');
  if (!blocks.length) return;
  withMermaid().then(function (mermaid) {
    blocks.forEach(function (block, i) {
      const div = el('div', 'mermaid', block.textContent);
      div.id = 'mermaid-' + Date.now() + '-' + i;
      block.parentElement.replaceWith(div);
    });
    mermaid.run({ querySelector: '#doc .mermaid' });
  }).catch(function () { /* diagrams stay as code blocks */ });
}

function fetchFile(relPath) {
  return fetch('/api/file?path=' + encodeURIComponent(relPath)).then(function (r) {
    if (!r.ok) throw new Error(r.status);
    return r.text();
  });
}

function openFile(relPath) {
  fetchFile(relPath).then(function (md) {
    currentPath = relPath;
    document.getElementById('path').textContent = relPath;
    renderDoc(md);
    document.getElementById('content').scrollTop = 0;
    markActive();
    history.replaceState(null, '', '#' + encodeURIComponent(relPath));
  }).catch(function () {
    const doc = document.getElementById('doc');
    doc.textContent = '';
    doc.appendChild(el('p', 'empty', T.loadFailed));
  });
}

function firstFile(node, depth) {
  if (node.files && node.files.length) return node.files[0].path;
  for (const d of (node.dirs || [])) {
    if (depth === 0 && hiddenFolders.has(d.path)) continue;
    const f = firstFile(d, depth + 1);
    if (f) return f;
  }
  return null;
}

function loadTree() {
  return fetch('/api/tree').then(function (r) { return r.json(); }).then(function (tree) {
    lastTree = tree;
    rerenderTree();
    return tree;
  });
}

loadTree().then(function (tree) {
  let fromHash = '';
  try { fromHash = decodeURIComponent(location.hash.slice(1)); } catch (e) {}
  const target = fromHash || firstFile(tree, 0);
  if (target) openFile(target);
});

// Links to #<case>/<file> (from notes, chat, a bookmark) open that file.
window.addEventListener('hashchange', function () {
  let target = '';
  try { target = decodeURIComponent(location.hash.slice(1)); } catch (e) {}
  if (target && target !== currentPath) openFile(target);
});

// Live updates: the server watches the folder and pushes an event; the tree and the open
// document refresh in place, keeping the scroll position.
function refresh() {
  loadTree();
  if (!currentPath) return;
  const content = document.getElementById('content');
  const scrollTop = content.scrollTop;
  fetchFile(currentPath).then(function (md) { renderDoc(md); content.scrollTop = scrollTop; }).catch(function () {});
}

function setOnline(online) {
  statusEl.textContent = online ? T.live : T.offline;
  statusEl.classList.toggle('off', !online);
}
function connectLiveReload() {
  const es = new EventSource('/api/events');
  es.onopen = function () { setOnline(true); };
  es.onmessage = function () { refresh(); };
  es.onerror = function () { setOnline(false); es.close(); setTimeout(connectLiveReload, 2000); };
}
connectLiveReload();
</script>
</body>
</html>`;
}

// ------------------------------------------------------------------ live updates

const clients = new Set();
let broadcastTimer = null;
function scheduleBroadcast() {
  // Debounce: one save often produces several file-system events.
  clearTimeout(broadcastTimer);
  broadcastTimer = setTimeout(() => {
    for (const res of clients) {
      try { res.write('data: change\n\n'); } catch (e) { clients.delete(res); }
    }
  }, 250);
}

// Recursive fs.watch exists on macOS, Windows and Linux with Node 20+. Where it does not,
// fall back to polling a cheap signature of the tree.
function signature(dir) {
  let sig = '';
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) sig += entry.name + '{' + signature(full) + '}';
    else if (entry.name.endsWith('.md')) sig += entry.name + ':' + fs.statSync(full).mtimeMs + ';';
  }
  return sig;
}
try {
  fs.watch(ROOT, { recursive: true }, scheduleBroadcast);
} catch (e) {
  let last = signature(ROOT);
  setInterval(() => {
    let now;
    try { now = signature(ROOT); } catch (err) { return; }
    if (now !== last) { last = now; scheduleBroadcast(); }
  }, 1500).unref();
}

// ------------------------------------------------------------------ server

const ALLOWED_HOSTS = new Set([`127.0.0.1:${PORT}`, `localhost:${PORT}`]);

const server = http.createServer((req, res) => {
  // A page on another origin can make the browser send requests to localhost through DNS
  // rebinding; its Host header then carries the attacker's name, not ours.
  if (PUBLIC) {
    // Behind a tunnel the Host is the tunnel's name, so the password is the gate.
    if (!authorized(req.headers.authorization)) {
      res.writeHead(401, { 'Content-Type': 'text/plain; charset=utf-8', 'WWW-Authenticate': 'Basic realm="consilium", charset="UTF-8"' });
      res.end('authentication required');
      return;
    }
  } else if (!ALLOWED_HOSTS.has(String(req.headers.host || '').toLowerCase())) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('forbidden host');
    return;
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8', Allow: 'GET, HEAD' });
    res.end('method not allowed');
    return;
  }
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const common = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Cache-Control': 'no-store' };

  if (url.pathname === '/api/events') {
    res.writeHead(200, { ...common, 'Content-Type': 'text/event-stream; charset=utf-8', Connection: 'keep-alive' });
    res.write('retry: 2000\n\n');
    clients.add(res);
    const heartbeat = setInterval(() => { try { res.write(': heartbeat\n\n'); } catch (e) {} }, 20000);
    req.on('close', () => { clearInterval(heartbeat); clients.delete(res); });
    return;
  }

  if (url.pathname === '/api/tree') {
    let tree;
    try { tree = walk(ROOT); } catch (e) { tree = { dirs: [], files: [] }; }
    res.writeHead(200, { ...common, 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(tree));
    return;
  }

  if (url.pathname === '/api/file') {
    const abs = safeResolve(url.searchParams.get('path'));
    if (!abs) {
      res.writeHead(404, { ...common, 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('not found');
      return;
    }
    res.writeHead(200, { ...common, 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(fs.readFileSync(abs, 'utf8'));
    return;
  }

  if (url.pathname !== '/') {
    res.writeHead(404, { ...common, 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('not found');
    return;
  }
  const nonce = crypto.randomBytes(16).toString('base64');
  res.writeHead(200, {
    ...common,
    'Content-Type': 'text/html; charset=utf-8',
    // Only our own nonce-tagged script and the pinned CDN files may run; no remote images,
    // frames or form posts, so injected markup cannot phone home.
    'Content-Security-Policy': [
      "default-src 'none'",
      `script-src 'nonce-${nonce}' https://cdn.jsdelivr.net`,
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data:",
      "font-src 'self' data:",
      "connect-src 'self'",
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
    ].join('; '),
  });
  res.end(page(nonce));
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`consilium reader: port ${PORT} is busy. Is a reader already running? Try --port ${PORT + 1}.`);
  } else {
    console.error('consilium reader:', err.message);
  }
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  console.log(`Consilium reader: http://localhost:${PORT}  (cases: ${ROOT}; Ctrl+C to stop)`);
  if (PUBLIC) {
    console.log('Public mode: every request needs a password. Anyone with the URL and the password can read these cases.');
    console.log(`  user:     ${USER}`);
    console.log(`  password: ${PASSWORD}`);
    console.log(`Expose it with:  ngrok http ${PORT}`);
  }
});
