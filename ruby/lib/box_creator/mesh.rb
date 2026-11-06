# Indexed triangle mesh assembled from rings (side walls) and caps (flat faces).
module BoxCreator
  class Mesh
    attr_reader :verts, :tris

    def initialize
      @verts = []
      @tris = []
    end

    def add_ring(pts, z)
      first = @verts.size
      pts.each { |p| @verts << [p[0], p[1], z] }
      (first...(first + pts.size)).to_a
    end

    # Connects two loops of equal length. A wall faces away from the loop's
    # centre, or towards it when inward is true (cavities and holes).
    def wall(lower, upper, inward = false)
      n = lower.size
      raise "ring size mismatch: #{n} vs #{upper.size}" if n != upper.size
      i = 0
      while i < n
        j = i + 1 == n ? 0 : i + 1
        a = lower[i]
        b = lower[j]
        c = upper[j]
        d = upper[i]
        if inward
          @tris << [a, c, b] << [a, d, c]
        else
          @tris << [a, b, c] << [a, c, d]
        end
        i += 1
      end
    end

    def stack(rings, inward = false)
      i = 0
      while i + 1 < rings.size
        wall(rings[i], rings[i + 1], inward)
        i += 1
      end
    end

    # Flat face bounded by an outer loop and zero or more hole loops.
    def cap(outer, holes, up)
      ids = outer.dup
      coords = []
      outer.each { |v| coords << @verts[v][0] << @verts[v][1] }
      starts = []
      holes.each do |hole|
        starts << ids.size
        hole.each do |v|
          ids << v
          coords << @verts[v][0] << @verts[v][1]
        end
      end
      local = Earcut.triangulate(coords, starts)
      check_cap(coords, ids.size, starts, local)
      i = 0
      while i < local.size
        a = local[i]
        b = local[i + 1]
        c = local[i + 2]
        ccw = cross2(coords, a, b, c) > 0
        if ccw == up
          @tris << [ids[a], ids[b], ids[c]]
        else
          @tris << [ids[a], ids[c], ids[b]]
        end
        i += 3
      end
    end

    # Rotates 180 degrees about the x axis (keeps triangle orientation) and
    # moves the plane z = top onto z = 0.
    def flip_about_x(top)
      @verts = @verts.map { |v| [v[0], -v[1], top - v[2]] }
      self
    end

    def to_stl(title)
      out = [[title].pack('a80'), [@tris.size].pack('V')]
      @tris.each do |t|
        a = @verts[t[0]]
        b = @verts[t[1]]
        c = @verts[t[2]]
        ux = b[0] - a[0]
        uy = b[1] - a[1]
        uz = b[2] - a[2]
        vx = c[0] - a[0]
        vy = c[1] - a[1]
        vz = c[2] - a[2]
        nx = uy * vz - uz * vy
        ny = uz * vx - ux * vz
        nz = ux * vy - uy * vx
        len = Math.sqrt(nx * nx + ny * ny + nz * nz)
        len = 1.0 if len == 0.0
        out << [nx / len, ny / len, nz / len,
                a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]].pack('e12') << "\0\0"
      end
      out.join
    end

    private

    def cross2(coords, a, b, c)
      ax = coords[2 * a]
      ay = coords[2 * a + 1]
      (coords[2 * b] - ax) * (coords[2 * c + 1] - ay) -
        (coords[2 * b + 1] - ay) * (coords[2 * c] - ax)
    end

    # A hole in the mesh is far worse than an error message: refuse to continue
    # unless the triangles cover the face exactly and use every vertex.
    def check_cap(coords, count, starts, local)
      used = Array.new(count, false)
      local.each { |v| used[v] = true }
      raise 'triangulation dropped a vertex' if used.include?(false)
      covered = 0.0
      i = 0
      while i < local.size
        covered += cross2(coords, local[i], local[i + 1], local[i + 2]).abs / 2.0
        i += 3
      end
      bounds = starts + [count]
      expected = loop_area(coords, 0, bounds[0]).abs
      k = 0
      while k + 1 < bounds.size
        expected -= loop_area(coords, bounds[k], bounds[k + 1]).abs
        k += 1
      end
      raise 'triangulation does not cover the face' if (covered - expected).abs > 1e-6 * (expected + 1.0)
    end

    def loop_area(coords, first, last)
      sum = 0.0
      i = first
      while i < last
        j = i + 1 == last ? first : i + 1
        sum += coords[2 * i] * coords[2 * j + 1] - coords[2 * j] * coords[2 * i + 1]
        i += 1
      end
      sum / 2.0
    end
  end
end
