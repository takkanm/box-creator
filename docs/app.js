import { makeZip } from './zip.js';

const DEBOUNCE_MS = 300;

const SNAP_ONLY = '!shape=cyl,closure=screw';
const SCREW_ONLY = 'shape=cyl,closure=screw';

// [key, label, default, step, condition]
// A condition lists key=value pairs that must all match; a leading ! hides on a match.
const ADVANCED = [
  ['r_out', '外側の縦の角の丸め半径 R_OUT', 5, 0.5, 'shape=rect'],
  ['lid_wall', '蓋の側壁の厚み', 2, 0.1],
  ['lid_topwall', '蓋の天面の厚み', 2, 0.1],
  ['fit', 'lip と蓋の隙間（片側）', 0.2, 0.05, SNAP_ONLY],
  ['lip_h', 'lip の高さ', 8, 0.5],
  ['lip_chamf', 'lip 上端の面取り', 0.8, 0.1],
  ['mouth_chamf', '蓋の開口部の面取り', 0.6, 0.1],
  ['r_top', '蓋の天面の縁の丸め', 1.5, 0.1],
  ['base_wall', '下箱の壁の厚み（空洞）', 2, 0.1, 'content=hollow'],
  ['floor_hollow', '底の厚み（空洞）', 2, 0.5, 'content=hollow'],
  ['floor_holes', '底の厚み（穴あり）', 3, 0.5, 'content=holes'],
  ['hole_clear', '穴の遊び（直径に足す）', 1, 0.1, 'content=holes'],
  ['hole_chamf', '穴の入口の面取り', 1, 0.1, 'content=holes'],
  ['min_wall', '最小の壁厚', 3, 0.5, 'content=holes'],
  ['bump', 'rib の飛び出し', 0.5, 0.05, SNAP_ONLY],
  ['bump_r', 'rib の断面の半径', 1.2, 0.05, SNAP_ONLY],
  ['groove_depth', '溝の深さ', 0.6, 0.05, SNAP_ONLY],
  ['groove_r', '溝の断面の半径', 1.35, 0.05, SNAP_ONLY],
  ['rib_pct', 'rib の長さ（長辺に対する %）', 45, 1, 'shape=rect'],
  ['rib_arc', 'rib の長さ（周方向）', 15, 0.5, 'shape=cyl,closure=snap'],
  ['thread_pitch', 'ネジのピッチ', 3, 0.1, SCREW_ONLY],
  ['thread_depth', 'ネジ山の深さ', 1, 0.1, SCREW_ONLY],
  ['thread_clear', 'ネジの隙間（半径方向）', 0.35, 0.05, SCREW_ONLY],
  ['segs', '円の分割数（1 周あたり）', 128, 4],
];

const SUMMARY_ROWS = [
  ['outer_size', '外形', 'mm'],
  ['h', '全高', 'mm'],
  ['base_h', '下箱の外から見える高さ', 'mm'],
  ['top_z', '下箱の上端', 'mm'],
  ['lid_h', '蓋の高さ', 'mm'],
  ['base_inner', '下箱の中', 'mm'],
  ['base_depth', '下箱の中の深さ', 'mm'],
  ['lid_inner', '蓋の中', 'mm'],
  ['hole_dia', '穴の直径', 'mm'],
  ['hole_grid', '穴の並び', ''],
  ['hole_pitch', '穴の間隔', 'mm'],
  ['hole_pitch_y', '行の間隔', 'mm'],
  ['max_cyl_len', '収納できる円筒の長さ', 'mm 以下'],
  ['rib_len', 'rib の長さ', 'mm'],
  ['thread_pitch', 'ネジのピッチ', 'mm'],
  ['thread_turns', 'ネジのかかり', '周'],
];

const form = document.getElementById('form');
const advanced = document.getElementById('advanced');
const statusEl = document.getElementById('status');
const overlay = document.getElementById('overlay');
const summaryEl = document.getElementById('summary');
const warningsEl = document.getElementById('warnings');
const downloadButtons = [...document.querySelectorAll('[data-download]')];

let preview = null;
let latest = null; // last valid result: { base, lid, ring, info }
let requestId = 0;
let busy = false;
let queued = false;
let timer = 0;
let dirty = false; // the form changed and no request has been sent for it yet
let advancedAutoOpened = false; // opened only to show an error, not by the user

function buildAdvancedFields() {
  const box = document.getElementById('advanced-fields');
  for (const [key, label, value, step, condition] of ADVANCED) {
    const field = document.createElement('div');
    field.className = 'field';
    field.dataset.field = key;
    if (condition) field.dataset.show = condition;
    const id = `f-${key}`;
    field.innerHTML = `<label for="${id}">${label}</label><input id="${id}" name="${key}" type="number" step="${step}" value="${value}">`;
    box.append(field);
  }
}

function formValues() {
  return Object.fromEntries(new FormData(form).entries());
}

function paramsText() {
  return Object.entries(formValues()).map(([k, v]) => `${k}=${v}`).join('\n');
}

function matches(condition, values) {
  const negated = condition.startsWith('!');
  const all = condition.replace('!', '').split(',').every((pair) => {
    const [key, value] = pair.split('=');
    return values[key] === value;
  });
  return negated ? !all : all;
}

// A square lid cannot turn, so the screw closure is for round boxes only.
function syncClosure() {
  const rect = form.elements.shape.value === 'rect';
  const [snap, screw] = form.elements.closure;
  screw.disabled = rect;
  if (rect) snap.checked = true;
}

function syncVisibility() {
  syncClosure();
  const values = formValues();
  for (const el of document.querySelectorAll('[data-show]')) {
    el.hidden = !matches(el.dataset.show, values);
  }
  document.getElementById('split-label').textContent = values.split === 'base' ? '下箱の高さ' : '蓋の高さ';
}

function clearErrors() {
  for (const el of form.querySelectorAll('.invalid')) {
    el.classList.remove('invalid', 'wide');
    el.querySelector('.error')?.remove();
    el.querySelector('input')?.removeAttribute('aria-invalid');
  }
}

function showErrors(errors) {
  clearErrors();
  for (const { field, message } of errors) {
    const el = form.querySelector(`[data-field="${field}"]`);
    if (!el) continue;
    if (advanced.contains(el) && !advanced.open) {
      advanced.open = true;
      advancedAutoOpened = true;
    }
    el.classList.add('invalid', 'wide');
    const text = document.createElement('p');
    text.className = 'error';
    text.textContent = message;
    el.append(text);
    el.querySelector('input').setAttribute('aria-invalid', 'true');
  }
  overlay.textContent = errors[0].message;
  overlay.hidden = false;
  setDownloadsEnabled(false);
  statusEl.textContent = `入力を確認してください（${errors.length} 件）`;
}

function setDownloadsEnabled(on) {
  for (const button of downloadButtons) button.disabled = !on;
}

function parseInfo(text) {
  const info = { warnings: [] };
  for (const line of text.split('\n').slice(1)) {
    const eq = line.indexOf('=');
    const key = line.slice(0, eq);
    const value = line.slice(eq + 1);
    if (key === 'warn') info.warnings.push(value);
    else info[key] = value;
  }
  return info;
}

function showSummary(info) {
  summaryEl.replaceChildren();
  for (const [key, label, unit] of SUMMARY_ROWS) {
    if (info[key] === undefined || info[key] === '0') continue;
    const dt = document.createElement('dt');
    const dd = document.createElement('dd');
    dt.textContent = label;
    let value = info[key];
    if (key === 'hole_grid') {
      const [rows, cols] = value.split('x');
      value = info.hole_ring ? `円周上（半径 ${info.hole_ring} mm）` : `${rows} 行 × ${cols} 列`;
    }
    dd.textContent = unit ? `${value} ${unit}` : value;
    summaryEl.append(dt, dd);
  }
  warningsEl.replaceChildren(...info.warnings.map((text) => {
    const li = document.createElement('li');
    li.textContent = text;
    return li;
  }));
}

function triangleCount(buffer) {
  return new DataView(buffer).getUint32(80, true);
}

function showResult(message) {
  clearErrors();
  if (advancedAutoOpened) {
    advanced.open = false;
    advancedAutoOpened = false;
  }
  overlay.hidden = true;
  const info = parseInfo(message.info);
  latest = { ...message, parsed: info, name: fileStem() };
  showSummary(info);
  setDownloadsEnabled(true);
  const tris = triangleCount(message.base) + triangleCount(message.lid);
  statusEl.textContent = `${Math.round(message.ms)} ms で生成 · ${tris.toLocaleString('ja-JP')} 三角形`;
  preview?.update(message.base, message.lid, {
    h: Number(info.h), topZ: Number(info.top_z), baseH: Number(info.base_h),
  });
}

function fileStem() {
  const v = formValues();
  const size = v.shape === 'cyl' ? `D${v.dia}` : `${v.w}x${v.d}`;
  return `box_${size}x${v.h}`;
}

function regenerate() {
  if (busy) {
    queued = true;
    return;
  }
  busy = true;
  dirty = false;
  statusEl.textContent = '生成中…';
  worker.postMessage({ id: ++requestId, params: paramsText() });
}

const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });

worker.onmessage = ({ data }) => {
  busy = false;
  if (queued) {
    queued = false;
    regenerate();
    return; // newer input is waiting, this result is already stale
  }
  if (data.fatal) {
    overlay.textContent = `生成に失敗しました: ${data.fatal}`;
    overlay.hidden = false;
    setDownloadsEnabled(false);
    statusEl.textContent = '生成に失敗しました';
  } else if (data.errors) {
    showErrors(data.errors);
  } else {
    showResult(data);
    if (dirty) setDownloadsEnabled(false);
  }
};

worker.onerror = (event) => {
  busy = false;
  overlay.textContent = `生成エンジンを読み込めませんでした: ${event.message}`;
  overlay.hidden = false;
  statusEl.textContent = '読み込みに失敗しました';
};

function saveBlob(blob, name) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

function download(kind) {
  if (!latest) return;
  const stem = latest.name;
  const files = {
    base: { name: `${stem}_base.stl`, buffer: latest.base },
    lid: { name: `${stem}_lid.stl`, buffer: latest.lid },
    ring: { name: `${stem}_fit_ring.stl`, buffer: latest.ring },
  };
  if (kind === 'zip') {
    const entries = Object.values(files).map(({ name, buffer }) => ({ name, bytes: new Uint8Array(buffer) }));
    saveBlob(makeZip(entries), `${stem}.zip`);
  } else {
    saveBlob(new Blob([files[kind].buffer], { type: 'model/stl' }), files[kind].name);
  }
}

// Keeps the same box when switching which height is entered.
function flipSplitValue() {
  const { h, content, floor_hollow, floor_holes, lid_topwall } = formValues();
  const floor = content === 'holes' ? floor_holes : floor_hollow;
  const height = Number(h) + Number(floor) + Number(lid_topwall);
  const input = form.elements.split_h;
  input.value = Math.round((height - Number(input.value)) * 100) / 100;
}

form.addEventListener('submit', (event) => event.preventDefault());

form.addEventListener('input', (event) => {
  if (event.target.name === 'split') flipSplitValue();
  syncVisibility();
  // What is on screen no longer matches the form, so it must not be downloaded.
  dirty = true;
  setDownloadsEnabled(false);
  clearTimeout(timer);
  timer = setTimeout(regenerate, DEBOUNCE_MS);
});

advanced.querySelector('summary').addEventListener('click', () => {
  advancedAutoOpened = false; // the user has taken over
});

document.getElementById('reset-advanced').addEventListener('click', () => {
  for (const [key, , value] of ADVANCED) form.elements[key].value = value;
  setDownloadsEnabled(false);
  regenerate();
});

for (const button of downloadButtons) {
  button.addEventListener('click', () => download(button.dataset.download));
}

for (const radio of document.querySelectorAll('input[name="view"]')) {
  radio.addEventListener('change', () => preview?.setExploded(radio.value === 'exploded'));
}

const sectionToggle = document.getElementById('section');
const sectionPos = document.getElementById('section-pos');
sectionToggle.addEventListener('change', () => {
  sectionPos.disabled = !sectionToggle.checked;
  preview?.setSection(sectionToggle.checked);
});
sectionPos.addEventListener('input', () => preview?.setSectionPos(Number(sectionPos.value)));
document.getElementById('reset-view').addEventListener('click', () => preview?.frame());

buildAdvancedFields();
syncVisibility();
regenerate();

// The preview is optional: generation and downloads work without the CDN.
import('./preview.js')
  .then(({ Preview }) => {
    preview = new Preview(document.getElementById('viewer'));
    if (latest) {
      const info = latest.parsed;
      preview.update(latest.base, latest.lid, { h: Number(info.h), topZ: Number(info.top_z), baseH: Number(info.base_h) });
    }
  })
  .catch((error) => {
    overlay.textContent = `プレビューを読み込めませんでした（STL のダウンロードは使えます）: ${error.message}`;
    overlay.hidden = false;
  });
