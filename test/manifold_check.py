#!/usr/bin/env python3
"""Independent check with manifold3d: pip install manifold3d numpy.

Reads STLs written by test/export_cases.rb and confirms that manifold3d accepts
each one and that base and lid share no volume when assembled.
Usage: manifold_check.py <dir>
"""
import glob
import os
import struct
import sys

import numpy as np
from manifold3d import Manifold, Mesh


def load(path):
    data = open(path, "rb").read()
    count = struct.unpack_from("<I", data, 80)[0]
    rows = np.frombuffer(data, dtype=np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")]), count=count, offset=84)
    verts, inverse = np.unique(rows["v"].reshape(-1, 3), axis=0, return_inverse=True)
    return Manifold(Mesh(verts.astype(np.float32), inverse.reshape(-1, 3).astype(np.uint32)))


def report(root):
    failed = False
    for base_path in sorted(glob.glob(os.path.join(root, "*_base.stl"))):
        stem = base_path[: -len("_base.stl")]
        height = float(open(stem + ".h").read())
        base = load(base_path)
        lid = load(stem + "_lid.stl")
        ring = load(stem + "_ring.stl")
        statuses = [m.status().name for m in (base, lid, ring)]
        assembled = lid.rotate((180, 0, 0)).translate((0, 0, height))
        overlap = (base ^ assembled).volume()
        genus = base.genus(), lid.genus(), ring.genus()
        ok = all(s == "NoError" for s in statuses) and overlap < 1e-6
        failed = failed or not ok
        print(f"{os.path.basename(stem):10} status={statuses[0]}/{statuses[1]}/{statuses[2]} "
              f"volume base={base.volume():.1f} lid={lid.volume():.1f} ring={ring.volume():.1f} "
              f"genus={genus} overlap={overlap:.6f} {'OK' if ok else 'FAIL'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(report(sys.argv[1]))
