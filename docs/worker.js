// Runs the mruby generator off the main thread.
import createBoxModule from './box.js';

const PART = { base: 0, lid: 1, ring: 2, info: 3, adjust: 4 };

const ready = createBoxModule().then((mod) => ({
  mod,
  generate: mod.cwrap('box_generate', 'number', ['number', 'number', 'number']),
}));

function call({ mod, generate }, params, part) {
  const input = mod.stringToNewUTF8(params);
  const lenPtr = mod._malloc(4);
  const ptr = generate(input, part, lenPtr);
  const len = mod.HEAP32[lenPtr >> 2];
  const bytes = mod.HEAPU8.slice(ptr, ptr + Math.abs(len));
  mod._free(ptr);
  mod._free(lenPtr);
  mod._free(input);
  if (len < 0) throw new Error(new TextDecoder().decode(bytes));
  return bytes;
}

function parseErrors(text) {
  return text.split('\n').slice(1).map((line) => {
    const tab = line.indexOf('\t');
    return { field: line.slice(0, tab), message: line.slice(tab + 1) };
  });
}

// Lines added after the input override it, so the corrected values can simply
// be appended to the parameters.
function parseAdjusted(text) {
  return text.split('\n').slice(1).filter(Boolean);
}

self.onmessage = async ({ data: { id, params, auto } }) => {
  try {
    const box = await ready;
    const started = performance.now();
    const changes = auto ? parseAdjusted(new TextDecoder().decode(call(box, params, PART.adjust))) : [];
    const input = [params, ...changes].join('\n');
    const adjusted = Object.fromEntries(changes.map((line) => line.split('=')));
    const infoText = new TextDecoder().decode(call(box, input, PART.info));
    if (infoText.startsWith('!ERR')) {
      self.postMessage({ id, adjusted, errors: parseErrors(infoText) });
      return;
    }
    const base = call(box, input, PART.base).buffer;
    const lid = call(box, input, PART.lid).buffer;
    const ring = call(box, input, PART.ring).buffer;
    const ms = performance.now() - started;
    self.postMessage({ id, adjusted, info: infoText, base, lid, ring, ms }, [base, lid, ring]);
  } catch (error) {
    self.postMessage({ id, fatal: String(error.message || error) });
  }
};
