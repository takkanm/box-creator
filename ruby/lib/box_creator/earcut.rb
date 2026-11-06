# Ruby port of earcut (https://github.com/mapbox/earcut, ISC License,
# Copyright (c) 2024 Mapbox).
#
# One deliberate difference from upstream: collinear vertices are KEPT.
# Upstream drops them, which is fine for rendering but would leave T-junctions
# here, because a horizontal face has to share every vertex of the side walls
# it joins. Only exact duplicates and zero-width spikes are removed.
module BoxCreator
  module Earcut
    class Node
      attr_accessor :i, :x, :y, :prev, :next, :z, :prev_z, :next_z

      def initialize(i, x, y)
        @i = i
        @x = x
        @y = y
        @prev = nil
        @next = nil
        @z = 0
        @prev_z = nil
        @next_z = nil
      end
    end

    HASH_THRESHOLD = 80

    # Ears thinner than this (twice their area, in mm^2) are put off until no
    # other ear is left. Slivers can turn over when vertices are rounded to the
    # float32 precision of STL.
    SLIVER_LIMIT = 1e-3

    # coords: flat [x0, y0, x1, y1, ...]; hole_starts: vertex index of each hole.
    # Returns a flat array of vertex indices, three per triangle.
    def self.triangulate(coords, hole_starts = [])
      count = coords.size / 2
      outer_end = hole_starts.empty? ? count : hole_starts[0]
      outer = linked_list(coords, 0, outer_end, true)
      triangles = []
      return triangles if outer.nil? || outer.next.equal?(outer.prev)

      outer = eliminate_holes(coords, hole_starts, outer) unless hole_starts.empty?

      min_x = nil
      min_y = nil
      inv_size = nil
      if count > HASH_THRESHOLD
        min_x = coords[0]
        min_y = coords[1]
        max_x = min_x
        max_y = min_y
        i = 0
        while i < outer_end
          x = coords[2 * i]
          y = coords[2 * i + 1]
          min_x = x if x < min_x
          min_y = y if y < min_y
          max_x = x if x > max_x
          max_y = y if y > max_y
          i += 1
        end
        size = max_x - min_x
        size = max_y - min_y if max_y - min_y > size
        inv_size = size > 0 ? 32767.0 / size : nil
      end

      index_curve(outer, min_x, min_y, inv_size) if inv_size
      earcut_linked(outer, triangles, min_x, min_y, inv_size)
      triangles
    end

    def self.linked_list(coords, first, last_exclusive, clockwise)
      node = nil
      if clockwise == (signed_area(coords, first, last_exclusive) > 0)
        i = first
        while i < last_exclusive
          node = insert_node(i, coords[2 * i], coords[2 * i + 1], node)
          i += 1
        end
      else
        i = last_exclusive - 1
        while i >= first
          node = insert_node(i, coords[2 * i], coords[2 * i + 1], node)
          i -= 1
        end
      end
      if node && equals(node, node.next)
        remove_node(node)
        node = node.next
      end
      node
    end

    def self.signed_area(coords, first, last_exclusive)
      sum = 0.0
      j = last_exclusive - 1
      i = first
      while i < last_exclusive
        sum += (coords[2 * j] - coords[2 * i]) * (coords[2 * i + 1] + coords[2 * j + 1])
        j = i
        i += 1
      end
      sum
    end

    # Removes duplicates and spikes, keeps collinear vertices.
    def self.filter_points(start, stop = nil)
      return start if start.nil?
      stop = start if stop.nil?
      p = start
      loop do
        again = false
        if equals(p, p.next) || equals(p.prev, p.next)
          remove_node(p)
          p = stop = p.prev
          break if p.equal?(p.next)
          again = true
        else
          p = p.next
        end
        break unless again || !p.equal?(stop)
      end
      stop
    end

    def self.earcut_linked(ear, triangles, min_x, min_y, inv_size, pass = 0)
      return if ear.nil?
      stop = ear
      limit = pass == 0 ? SLIVER_LIMIT : 0.0
      until ear.prev.equal?(ear.next)
        prev = ear.prev
        nxt = ear.next
        if inv_size ? ear_hashed?(ear, min_x, min_y, inv_size, limit) : ear?(ear, limit)
          triangles << prev.i << ear.i << nxt.i
          remove_node(ear)
          ear = nxt.next
          stop = nxt.next
          next
        end
        ear = nxt
        if ear.equal?(stop)
          if pass == 0
            earcut_linked(filter_points(ear), triangles, min_x, min_y, inv_size, 1)
          elsif pass == 1
            split_earcut(ear, triangles, min_x, min_y, inv_size)
          end
          break
        end
      end
    end

    def self.ear?(ear, limit)
      a = ear.prev
      c = ear.next
      return false if area(a, ear, c) >= 0 || area(a, ear, c) > -limit
      ax = a.x
      ay = a.y
      bx = ear.x
      by = ear.y
      cx = c.x
      cy = c.y
      x0 = min3(ax, bx, cx)
      y0 = min3(ay, by, cy)
      x1 = max3(ax, bx, cx)
      y1 = max3(ay, by, cy)
      p = c.next
      until p.equal?(a)
        if p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 &&
           point_in_triangle_except_first(ax, ay, bx, by, cx, cy, p.x, p.y) &&
           area(p.prev, p, p.next) >= 0
          return false
        end
        p = p.next
      end
      true
    end

    def self.ear_hashed?(ear, min_x, min_y, inv_size, limit)
      a = ear.prev
      c = ear.next
      return false if area(a, ear, c) >= 0 || area(a, ear, c) > -limit
      ax = a.x
      ay = a.y
      bx = ear.x
      by = ear.y
      cx = c.x
      cy = c.y
      x0 = min3(ax, bx, cx)
      y0 = min3(ay, by, cy)
      x1 = max3(ax, bx, cx)
      y1 = max3(ay, by, cy)
      min_z = z_order(x0, y0, min_x, min_y, inv_size)
      max_z = z_order(x1, y1, min_x, min_y, inv_size)

      p = ear.prev_z
      while p && p.z >= min_z
        return false if blocks_ear?(p, a, c, ax, ay, bx, by, cx, cy, x0, y0, x1, y1)
        p = p.prev_z
      end
      n = ear.next_z
      while n && n.z <= max_z
        return false if blocks_ear?(n, a, c, ax, ay, bx, by, cx, cy, x0, y0, x1, y1)
        n = n.next_z
      end
      true
    end

    def self.blocks_ear?(p, a, c, ax, ay, bx, by, cx, cy, x0, y0, x1, y1)
      p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 &&
        !p.equal?(a) && !p.equal?(c) &&
        point_in_triangle_except_first(ax, ay, bx, by, cx, cy, p.x, p.y) &&
        area(p.prev, p, p.next) >= 0
    end

    def self.split_earcut(start, triangles, min_x, min_y, inv_size)
      a = start
      loop do
        b = a.next.next
        until b.equal?(a.prev)
          if !a.i.equal?(b.i) && a.i != b.i && valid_diagonal?(a, b)
            c = split_polygon(a, b)
            a = filter_points(a, a.next)
            c = filter_points(c, c.next)
            earcut_linked(a, triangles, min_x, min_y, inv_size, 0)
            earcut_linked(c, triangles, min_x, min_y, inv_size, 0)
            return
          end
          b = b.next
        end
        a = a.next
        break if a.equal?(start)
      end
    end

    def self.eliminate_holes(coords, hole_starts, outer)
      queue = []
      count = coords.size / 2
      hole_starts.each_with_index do |first, idx|
        last = idx + 1 < hole_starts.size ? hole_starts[idx + 1] : count
        queue << leftmost(linked_list(coords, first, last, false))
      end
      queue = queue.sort { |a, b| compare_xy(a, b) }
      queue.each { |hole| outer = eliminate_hole(hole, outer) }
      outer
    end

    def self.compare_xy(a, b)
      return a.x <=> b.x if a.x != b.x
      return a.y <=> b.y if a.y != b.y
      a_slope = (a.next.y - a.y) / (a.next.x - a.x)
      b_slope = (b.next.y - b.y) / (b.next.x - b.x)
      a_slope <=> b_slope
    end

    def self.eliminate_hole(hole, outer)
      bridge = find_hole_bridge(hole, outer)
      return outer if bridge.nil?
      bridge_reverse = split_polygon(bridge, hole)
      filter_points(bridge_reverse, bridge_reverse.next)
      filter_points(bridge, bridge.next)
    end

    def self.find_hole_bridge(hole, outer)
      p = outer
      hx = hole.x
      hy = hole.y
      qx = nil
      m = nil
      return p if equals(hole, p)
      loop do
        return p.next if equals(hole, p.next)
        if hy <= p.y && hy >= p.next.y && p.next.y != p.y
          x = p.x + (hy - p.y) * (p.next.x - p.x) / (p.next.y - p.y)
          if x <= hx && (qx.nil? || x > qx)
            qx = x
            m = p.x < p.next.x ? p : p.next
            return m if x == hx
          end
        end
        p = p.next
        break if p.equal?(outer)
      end
      return nil if m.nil?

      stop = m
      mx = m.x
      my = m.y
      tan_min = nil
      p = m
      loop do
        if hx >= p.x && p.x >= mx && hx != p.x &&
           point_in_triangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, p.x, p.y)
          tan = (hy - p.y).abs / (hx - p.x)
          if locally_inside?(p, hole) &&
             (tan_min.nil? || tan < tan_min ||
              (tan == tan_min && (p.x > m.x || (p.x == m.x && sector_contains_sector?(m, p)))))
            m = p
            tan_min = tan
          end
        end
        p = p.next
        break if p.equal?(stop)
      end
      m
    end

    def self.sector_contains_sector?(m, p)
      area(m.prev, m, p.prev) < 0 && area(p.next, m, m.next) < 0
    end

    # z-order index: nodes are sorted once and relinked through prev_z/next_z.
    def self.index_curve(start, min_x, min_y, inv_size)
      nodes = []
      p = start
      loop do
        p.z = z_order(p.x, p.y, min_x, min_y, inv_size)
        nodes << p
        p = p.next
        break if p.equal?(start)
      end
      nodes = nodes.sort { |a, b| a.z <=> b.z }
      prev = nil
      nodes.each do |node|
        node.prev_z = prev
        node.next_z = nil
        prev.next_z = node if prev
        prev = node
      end
    end

    def self.z_order(x, y, min_x, min_y, inv_size)
      xi = ((x - min_x) * inv_size).to_i
      yi = ((y - min_y) * inv_size).to_i
      xi = (xi | (xi << 8)) & 0x00FF00FF
      xi = (xi | (xi << 4)) & 0x0F0F0F0F
      xi = (xi | (xi << 2)) & 0x33333333
      xi = (xi | (xi << 1)) & 0x55555555
      yi = (yi | (yi << 8)) & 0x00FF00FF
      yi = (yi | (yi << 4)) & 0x0F0F0F0F
      yi = (yi | (yi << 2)) & 0x33333333
      yi = (yi | (yi << 1)) & 0x55555555
      xi | (yi << 1)
    end

    def self.leftmost(start)
      p = start
      best = start
      loop do
        best = p if p.x < best.x || (p.x == best.x && p.y < best.y)
        p = p.next
        break if p.equal?(start)
      end
      best
    end

    def self.point_in_triangle(ax, ay, bx, by, cx, cy, px, py)
      (cx - px) * (ay - py) >= (ax - px) * (cy - py) &&
        (ax - px) * (by - py) >= (bx - px) * (ay - py) &&
        (bx - px) * (cy - py) >= (cx - px) * (by - py)
    end

    def self.point_in_triangle_except_first(ax, ay, bx, by, cx, cy, px, py)
      !(ax == px && ay == py) && point_in_triangle(ax, ay, bx, by, cx, cy, px, py)
    end

    def self.valid_diagonal?(a, b)
      a.next.i != b.i && a.prev.i != b.i && !intersects_polygon?(a, b) &&
        locally_inside?(a, b) && locally_inside?(b, a) && middle_inside?(a, b) &&
        (area(a.prev, a, b.prev) != 0 || area(a, b.prev, b) != 0)
    end

    def self.area(p, q, r)
      (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
    end

    def self.equals(a, b)
      a.x == b.x && a.y == b.y
    end

    def self.sign(v)
      v > 0 ? 1 : (v < 0 ? -1 : 0)
    end

    def self.intersects?(p1, q1, p2, q2)
      o1 = sign(area(p1, q1, p2))
      o2 = sign(area(p1, q1, q2))
      o3 = sign(area(p2, q2, p1))
      o4 = sign(area(p2, q2, q1))
      return true if o1 != o2 && o3 != o4
      return true if o1 == 0 && on_segment?(p1, p2, q1)
      return true if o2 == 0 && on_segment?(p1, q2, q1)
      return true if o3 == 0 && on_segment?(p2, p1, q2)
      return true if o4 == 0 && on_segment?(p2, q1, q2)
      false
    end

    def self.on_segment?(p, q, r)
      q.x <= max2(p.x, r.x) && q.x >= min2(p.x, r.x) &&
        q.y <= max2(p.y, r.y) && q.y >= min2(p.y, r.y)
    end

    def self.intersects_polygon?(a, b)
      p = a
      loop do
        if p.i != a.i && p.next.i != a.i && p.i != b.i && p.next.i != b.i &&
           intersects?(p, p.next, a, b)
          return true
        end
        p = p.next
        break if p.equal?(a)
      end
      false
    end

    def self.locally_inside?(a, b)
      if area(a.prev, a, a.next) < 0
        area(a, b, a.next) >= 0 && area(a, a.prev, b) >= 0
      else
        area(a, b, a.prev) < 0 || area(a, a.next, b) < 0
      end
    end

    def self.middle_inside?(a, b)
      p = a
      inside = false
      px = (a.x + b.x) / 2.0
      py = (a.y + b.y) / 2.0
      loop do
        if (p.y > py) != (p.next.y > py) && p.next.y != p.y &&
           px < (p.next.x - p.x) * (py - p.y) / (p.next.y - p.y) + p.x
          inside = !inside
        end
        p = p.next
        break if p.equal?(a)
      end
      inside
    end

    def self.split_polygon(a, b)
      a2 = Node.new(a.i, a.x, a.y)
      b2 = Node.new(b.i, b.x, b.y)
      an = a.next
      bp = b.prev
      a.next = b
      b.prev = a
      a2.next = an
      an.prev = a2
      b2.next = a2
      a2.prev = b2
      bp.next = b2
      b2.prev = bp
      b2
    end

    def self.insert_node(i, x, y, last)
      node = Node.new(i, x, y)
      if last.nil?
        node.prev = node
        node.next = node
      else
        node.next = last.next
        node.prev = last
        last.next.prev = node
        last.next = node
      end
      node
    end

    def self.remove_node(p)
      p.next.prev = p.prev
      p.prev.next = p.next
      p.prev_z.next_z = p.next_z if p.prev_z
      p.next_z.prev_z = p.prev_z if p.next_z
    end

    def self.min2(a, b)
      a < b ? a : b
    end

    def self.max2(a, b)
      a > b ? a : b
    end

    def self.min3(a, b, c)
      min2(min2(a, b), c)
    end

    def self.max3(a, b, c)
      max2(max2(a, b), c)
    end
  end
end
