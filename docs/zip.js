// Minimal ZIP writer. Entries are stored uncompressed, which keeps this
// dependency-free; STL files are small here.
const CRC_TABLE = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function dosDateTime(date) {
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
  const day = ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  return { time, day };
}

// files: [{ name, bytes: Uint8Array }]
export function makeZip(files, date = new Date()) {
  const encoder = new TextEncoder();
  const { time, day } = dosDateTime(date);
  const chunks = [];
  const central = [];
  let offset = 0;

  for (const { name, bytes } of files) {
    const nameBytes = encoder.encode(name);
    const crc = crc32(bytes);
    const header = (signature, extra) => {
      const view = new DataView(new ArrayBuffer(extra + 26));
      view.setUint32(0, signature, true);
      let p = 4;
      if (extra === 20) { view.setUint16(p, 20, true); p += 2; } // version made by
      view.setUint16(p, 20, true); // version needed
      view.setUint16(p + 2, 0x0800, true); // UTF-8 names
      view.setUint16(p + 4, 0, true); // stored
      view.setUint16(p + 6, time, true);
      view.setUint16(p + 8, day, true);
      view.setUint32(p + 10, crc, true);
      view.setUint32(p + 14, bytes.length, true);
      view.setUint32(p + 18, bytes.length, true);
      view.setUint16(p + 22, nameBytes.length, true);
      return view;
    };

    const local = header(0x04034b50, 4);
    chunks.push(new Uint8Array(local.buffer), nameBytes, bytes);

    const entry = new DataView(new ArrayBuffer(46));
    new Uint8Array(entry.buffer).set(new Uint8Array(header(0x02014b50, 20).buffer).subarray(0, 46));
    entry.setUint32(42, offset, true);
    central.push(new Uint8Array(entry.buffer), nameBytes);

    offset += local.byteLength + nameBytes.length + bytes.length;
  }

  const centralSize = central.reduce((sum, c) => sum + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true);
  end.setUint16(8, files.length, true);
  end.setUint16(10, files.length, true);
  end.setUint32(12, centralSize, true);
  end.setUint32(16, offset, true);

  return new Blob([...chunks, ...central, new Uint8Array(end.buffer)], { type: 'application/zip' });
}
