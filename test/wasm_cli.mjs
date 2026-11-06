// Runs the built wasm from Node. Usage: node wasm_cli.mjs <out dir> < cases.txt
// Each input line is "<name>|<part>|<params separated by spaces>".
import { readFileSync, writeFileSync } from 'node:fs';
import createBoxModule from '../docs/box.js';

const mod = await createBoxModule();
const generate = mod.cwrap('box_generate', 'number', ['number', 'number', 'number']);
const outDir = process.argv[2];

for (const line of readFileSync(0, 'utf8').split('\n').filter(Boolean)) {
  const [name, part, spec] = line.split('|');
  const input = mod.stringToNewUTF8(spec.split(' ').join('\n'));
  const lenPtr = mod._malloc(4);
  const started = performance.now();
  const ptr = generate(input, Number(part), lenPtr);
  const ms = performance.now() - started;
  const len = mod.HEAP32[lenPtr >> 2];
  const bytes = mod.HEAPU8.slice(ptr, ptr + Math.abs(len));
  mod._free(ptr);
  mod._free(lenPtr);
  mod._free(input);
  writeFileSync(`${outDir}/${name}.bin`, bytes);
  console.log(`${name} len=${len} ${ms.toFixed(1)}ms`);
}
