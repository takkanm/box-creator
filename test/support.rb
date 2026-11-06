# Mesh checks that work on STL bytes only, so they see exactly what a slicer sees.
class StlMesh
  attr_reader :verts, :tris, :normals

  def initialize(bytes)
    count = bytes[80, 4].unpack1('V')
    raise 'bad STL size' unless bytes.bytesize == 84 + 50 * count
    index = {}
    @verts = []
    @tris = []
    @normals = []
    count.times do |i|
      f = bytes.byteslice(84 + 50 * i, 48).unpack('e12')
      @normals << f[0, 3]
      @tris << [3, 6, 9].map do |o|
        key = f[o, 3]
        index[key] ||= (@verts << key; @verts.size - 1)
      end
    end
  end

  # Returns a mesh moved into assembled position: undoes the print flip.
  def unflipped(top)
    copy = dup
    copy.instance_variable_set(:@verts, @verts.map { |v| [v[0], -v[1], top - v[2]] })
    copy
  end

  def bounds
    (0..2).map { |a| @verts.map { |v| v[a] }.minmax }
  end

  # Every directed edge must appear exactly once and be matched by its reverse.
  def edge_defects
    directed = Hash.new(0)
    @tris.each do |a, b, c|
      directed[[a, b]] += 1
      directed[[b, c]] += 1
      directed[[c, a]] += 1
    end
    directed.select { |(a, b), n| n != 1 || directed[[b, a]] != 1 }.keys
  end

  def degenerate_count(min_area = 1e-9)
    @tris.count { |t| area(t) < min_area }
  end

  def area(t)
    a, b, c = t.map { |i| @verts[i] }
    Math.sqrt(cross(sub(b, a), sub(c, a)).sum { |x| x * x }) / 2.0
  end

  def volume
    @tris.sum do |t|
      a, b, c = t.map { |i| @verts[i] }
      dot(a, cross(b, c)) / 6.0
    end
  end

  # Stored normals must agree with the winding order.
  def normal_mismatches
    @tris.each_with_index.count do |t, i|
      a, b, c = t.map { |k| @verts[k] }
      n = cross(sub(b, a), sub(c, a))
      dot(n, @normals[i]) <= 0
    end
  end

  # Pairs of triangles without a common vertex whose edges pierce each other.
  def self_intersections(cell = 5.0)
    grid = Hash.new { |h, k| h[k] = [] }
    boxes = @tris.map do |t|
      p = t.map { |i| @verts[i] }
      (0..2).map { |a| p.map { |v| v[a] }.minmax }
    end
    boxes.each_with_index do |b, i|
      ((b[0][0] / cell).floor..(b[0][1] / cell).floor).each do |x|
        ((b[1][0] / cell).floor..(b[1][1] / cell).floor).each do |y|
          grid[[x, y]] << i
        end
      end
    end
    seen = {}
    hits = []
    grid.each_value do |list|
      list.each_with_index do |i, n|
        list[(n + 1)..].each do |j|
          key = i < j ? [i, j] : [j, i]
          next if seen[key]
          seen[key] = true
          next unless (0..2).all? { |a| boxes[i][a][0] <= boxes[j][a][1] && boxes[j][a][0] <= boxes[i][a][1] }
          next unless (@tris[i] & @tris[j]).empty?
          hits << key if tris_cross?(@tris[i], @tris[j]) || tris_cross?(@tris[j], @tris[i])
        end
      end
    end
    hits
  end

  # Cross-section at z as 2D segments.
  def slice(z)
    segs = []
    @tris.each do |t|
      pts = []
      t.each_with_index do |vi, k|
        a = @verts[vi]
        b = @verts[t[(k + 1) % 3]]
        next if (a[2] - z) * (b[2] - z) >= 0
        u = (z - a[2]) / (b[2] - a[2])
        pts << [a[0] + u * (b[0] - a[0]), a[1] + u * (b[1] - a[1])]
      end
      segs << pts if pts.size == 2
    end
    segs
  end

  private

  def tris_cross?(s, t)
    a, b, c = t.map { |i| @verts[i] }
    n = cross(sub(b, a), sub(c, a))
    len = Math.sqrt(dot(n, n))
    return false if len < 1e-12
    s.each_with_index.any? do |vi, k|
      p = @verts[vi]
      q = @verts[s[(k + 1) % 3]]
      d1 = dot(n, sub(p, a)) / len
      d2 = dot(n, sub(q, a)) / len
      next false unless d1 * d2 < 0 && d1.abs > 1e-5 && d2.abs > 1e-5
      u = d1 / (d1 - d2)
      x = [p[0] + u * (q[0] - p[0]), p[1] + u * (q[1] - p[1]), p[2] + u * (q[2] - p[2])]
      inside_triangle?(x, a, b, c, n)
    end
  end

  def inside_triangle?(x, a, b, c, n)
    [[a, b], [b, c], [c, a]].all? do |p, q|
      dot(n, cross(sub(q, p), sub(x, p))) > 1e-9
    end
  end

  def sub(a, b)
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
  end

  def dot(a, b)
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
  end

  def cross(a, b)
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
  end
end

module Section
  module_function

  # Even-odd test: is (x, y) inside the material of this cross-section?
  def inside?(segs, x, y)
    count = 0
    segs.each do |a, b|
      next unless (a[1] > y) != (b[1] > y)
      count += 1 if x < a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
    end
    count.odd?
  end

  def point_segment_distance(p, a, b)
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    len = dx * dx + dy * dy
    t = len.zero? ? 0.0 : ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len
    t = t.clamp(0.0, 1.0)
    Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)
  end

  # Smallest distance from any point to the section outline.
  def gap(points, segs)
    points.map { |p| segs.map { |a, b| point_segment_distance(p, a, b) }.min }.min
  end

  # Crossings with the ray from the origin along +x or +y, nearest first.
  def ray_hits(segs, axis)
    other = 1 - axis
    segs.filter_map do |a, b|
      next unless (a[other] > 0) != (b[other] > 0)
      a[axis] + (0 - a[other]) * (b[axis] - a[axis]) / (b[other] - a[other])
    end.select(&:positive?).sort
  end
end
