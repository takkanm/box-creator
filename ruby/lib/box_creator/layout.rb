# Automatic placement of cylinder holes inside the lip outline.
module BoxCreator
  module Layout
    EPS = 1e-9

    # Inside distance from (x, y) to a rounded rectangle centred on the origin.
    def self.rect_inside_distance(x, y, w, h, r)
      qx = x.abs - (w / 2.0 - r)
      qy = y.abs - (h / 2.0 - r)
      ox = qx > 0 ? qx : 0.0
      oy = qy > 0 ? qy : 0.0
      inner = qx > qy ? qx : qy
      inner = 0.0 if inner > 0
      r - Math.sqrt(ox * ox + oy * oy) - inner
    end

    def self.equal_pitch(length, count, hole_d)
      return 0.0 if count < 2
      hole_d + (length - count * hole_d) / (count + 1)
    end

    def self.round_half(value)
      (value * 2.0).round / 2.0
    end

    def self.grid_points(rows, cols, count, px, py)
      list = []
      left = count
      row = 0
      while row < rows
        in_row = left < cols ? left : cols
        y = ((rows - 1) / 2.0 - row) * py
        c = 0
        while c < in_row
          list << [(c - (in_row - 1) / 2.0) * px, y]
          c += 1
        end
        left -= in_row
        row += 1
      end
      list
    end

    def self.spaced?(pts, hole_d, min_wall)
      limit = hole_d + min_wall - EPS
      i = 0
      while i < pts.size
        j = i + 1
        while j < pts.size
          dx = pts[i][0] - pts[j][0]
          dy = pts[i][1] - pts[j][1]
          return false if Math.sqrt(dx * dx + dy * dy) < limit
          j += 1
        end
        i += 1
      end
      true
    end

    # Grid along the long side. Equal gaps are rounded to a 0.5 mm pitch when the
    # walls allow it. Returns nil when nothing fits.
    def self.rect(w, h, r, hole_d, count, min_wall)
      long = w >= h ? w : h
      short = w >= h ? h : w
      best = nil
      best_score = nil
      rows = 1
      while rows <= count
        cols = (count + rows - 1) / rows
        break if cols < rows
        raw_x = equal_pitch(long, cols, hole_d)
        raw_y = equal_pitch(short, rows, hole_d)
        # rounding moves the pitch by 0.25 at most, so this rules out most grids cheaply
        reachable = (cols < 2 || raw_x + 0.25 >= hole_d + min_wall) && (rows < 2 || raw_y + 0.25 >= hole_d + min_wall)
        if reachable
          [[round_half(raw_x), round_half(raw_y)], [raw_x, raw_y]].each do |pitch|
            pts = grid_points(rows, cols, count, pitch[0], pitch[1])
            ok = spaced?(pts, hole_d, min_wall) && pts.all? do |p|
              x = w >= h ? p[0] : p[1]
              y = w >= h ? p[1] : p[0]
              rect_inside_distance(x, y, w, h, r) >= hole_d / 2.0 + min_wall - EPS
            end
            next unless ok
            min_pitch = cols > 1 ? pitch[0] : pitch[1]
            min_pitch = pitch[1] if rows > 1 && cols > 1 && pitch[1] < pitch[0]
            score = [rows * cols - count, -min_pitch]
            if best_score.nil? || (score <=> best_score) < 0
              best_score = score
              pts = pts.map { |p| [p[1], p[0]] } if w < h
              best = { :points => pts, :rows => rows, :cols => cols, :pitch_x => pitch[0], :pitch_y => pitch[1] }
            end
            break
          end
        end
        rows += 1
      end
      best
    end

    # One hole in the centre, otherwise an evenly spaced circle whose radius
    # balances the gap between holes against the gap to the lip.
    def self.circle(lip_r, hole_d, count, min_wall)
      hole_r = hole_d / 2.0
      if count == 1
        return nil if lip_r - hole_r < min_wall - EPS
        return { :points => [[0.0, 0.0]], :rows => 1, :cols => 1, :pitch_x => 0.0, :pitch_y => 0.0 }
      end
      sin_half = Math.sin(Math::PI / count)
      rho = (lip_r + hole_r) / (1.0 + 2.0 * sin_half)
      max_rho = lip_r - hole_r - min_wall
      min_rho = (hole_d + min_wall) / (2.0 * sin_half)
      return nil if min_rho > max_rho + EPS
      rho = max_rho if rho > max_rho
      rho = min_rho if rho < min_rho
      pts = []
      i = 0
      while i < count
        a = i * 2.0 * Math::PI / count
        pts << [rho * Math.cos(a), rho * Math.sin(a)]
        i += 1
      end
      { :points => pts, :rows => 1, :cols => count, :pitch_x => 2.0 * rho * sin_half, :pitch_y => 0.0, :ring_radius => rho }
    end
  end
end
