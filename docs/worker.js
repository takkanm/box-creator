// Runs the mruby generator off the main thread.
import createBoxModule from './box.js';

const PART = { base: 0, lid: 1, ring: 2, info: 3 };

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

self.onmessage = async ({ data: { id, params } }) => {
  try {
    const box = await ready;
    const started = performance.now();
    const infoText = new TextDecoder().decode(call(box, params, PART.info));
    if (infoText.startsWith('!ERR')) {
      self.postMessage({ id, errors: parseErrors(infoText) });
      return;
    }
    const base = call(box, params, PART.base).buffer;
    const lid = call(box, params, PART.lid).buffer;
    const ring = call(box, params, PART.ring).buffer;
    const ms = performance.now() - started;
    self.postMessage({ id, info: infoText, base, lid, ring, ms }, [base, lid, ring]);
  } catch (error) {
    self.postMessage({ id, fatal: String(error.message || error) });
  }
};
