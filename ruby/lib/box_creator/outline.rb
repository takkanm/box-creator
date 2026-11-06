# Closed cross-section loops. Every loop an outline makes is counter-clockwise
# seen from +z, and loops made with the same feature have the same vertex count
# and order, so neighbouring z levels can be stitched vertex by vertex.
module BoxCreator
  # A rib or groove: a stadium-shaped pad pushed along the loop normal. Its
  # cross-section is a circular segment and its ends are spherically rounded.
  class Feature
    END_STEPS = 6
    Z_STEPS = 6

    attr_reader :length, :radius, :height, :end_radius, :center_z, :ref_inset

    def initialize(length, radius, height, center_z, ref_inset)
      @length = length
      @radius = radius
      @height = height
      @center_z = center_z
      @ref_inset = ref_inset
      @end_radius = Feature.half_chord(radius, height)
    end

    def self.half_chord(radius, height)
      off = radius - height
      Math.sqrt(radius * radius - off * off)
    end

    # Positions along the loop where vertices are needed: the rounded ends only,
    # since the middle of the pad has a constant section.
    def breaks
      half = @length / 2.0
      cap = half - @end_radius
      positive = []
      i = 0
      while i <= END_STEPS
        positive << cap + @end_radius * Math.sin(i * Math::PI / 2.0 / END_STEPS)
        i += 1
      end
      positive.reverse.map { |s| -s } + positive
    end

    def z_levels
      levels = []
      i = -Z_STEPS
      while i <= Z_STEPS
        levels << @center_z + @end_radius * Math.sin(i * Math::PI / 2.0 / Z_STEPS)
        i += 1
      end
      levels
    end

    # Push distance at height z and position s along the loop.
    def offset_at(s, z)
      dz = (z - @center_z).abs
      past_cap = s.abs - (@length / 2.0 - @end_radius)
      dist = past_cap > 0 ? Math.sqrt(past_cap * past_cap + dz * dz) : dz
      return 0.0 if dist >= @end_radius
      Math.sqrt(@radius * @radius - dist * dist) - (@radius - @height)
    end
  end

  # A right-handed single-start thread with a 45 degree trapezoid profile. It is
  # applied ring by ring: each vertex moves radially by an amount that depends on
  # the thread phase at its height and angle, so a level stays a plain closed loop.
  #
  # The male and female sides use the same profile and the same phase. The female
  # radius is the male radius plus the clearance at every phase, so the parts cannot
  # collide anywhere along the helix. Near its ends a thread fades towards the side
  # that removes material, which keeps that guarantee.
  class Thread
    LEVELS_PER_PITCH = 24

    attr_reader :first_z, :last_z

    # male: pushes a root circle outward. Otherwise pushes a root circle inward.
    def initialize(pitch, depth, first_z, last_z, male)
      @pitch = pitch
      @depth = depth
      @first_z = first_z
      @last_z = last_z
      @male = male
      flat = pitch - 2.0 * depth
      @crest = flat * 0.4
    end

    def z_levels
      count = ((@last_z - @first_z) / @pitch * LEVELS_PER_PITCH).ceil
      levels = []
      i = 0
      while i <= count
        levels << @first_z + (@last_z - @first_z) * i / count
        i += 1
      end
      levels
    end

    # Full turns at full depth.
    def turns
      (@last_z - @first_z - @depth) / @pitch
    end

    def apply(pts, z)
      fade = fade_at(z)
      return pts if fade == 0.0
      pts.map do |p|
        angle = Math.atan2(p[1], p[0])
        height = profile(z / @pitch - angle / (2.0 * Math::PI))
        d = @male ? @depth * height * fade : -@depth * (1.0 - height) * fade
        radius = Math.sqrt(p[0] * p[0] + p[1] * p[1])
        scale = (radius + d) / radius
        [p[0] * scale, p[1] * scale]
      end
    end

    private

    def fade_at(z)
      low = (z - @first_z) / @depth
      high = (@last_z - z) / @depth
      f = low < high ? low : high
      return 0.0 if f <= 0.0
      f > 1.0 ? 1.0 : f
    end

    # 0 at the root, 1 at the crest. phase is in turns; one turn is one pitch.
    def profile(phase)
      t = (phase - phase.floor) * @pitch
      half_crest = @crest / 2.0
      centre = @pitch / 2.0
      d = (t - centre).abs
      return 1.0 if d <= half_crest
      slope = (d - half_crest) / @depth
      slope >= 1.0 ? 0.0 : 1.0 - slope
    end
  end

  class Ring
    attr_reader :pts

    # tags: [vertex index, normal x, normal y, position along the feature]
    def initialize(pts, tags)
      @pts = pts
      @tags = tags
    end

    def displaced(feature, z)
      out = @pts.map { |p| p }
      @tags.each do |tag|
        i = tag[0]
        d = feature.offset_at(tag[3], z)
        next if d == 0.0
        p = @pts[i]
        out[i] = [p[0] + tag[1] * d, p[1] + tag[2] * d]
      end
      out
    end
  end

  class RectOutline
    MIN_RADIUS = 0.2
    CORNER_STARTS = [[0.0, -1.0], [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0]].freeze

    attr_reader :w, :h, :r

    def initialize(w, h, r, segs)
      @w = w
      @h = h
      @r = r
      @corner_segs = segs / 4
      @long_x = w >= h
    end

    def radius_at(inset)
      w = @w - 2.0 * inset
      h = @h - 2.0 * inset
      limit = (w < h ? w : h) / 2.0 - 0.01
      r = @r - inset
      r = MIN_RADIUS if r < MIN_RADIUS
      r = limit if r > limit
      r
    end

    def size_at(inset)
      [@w - 2.0 * inset, @h - 2.0 * inset]
    end

    # Length of the straight part of the long side.
    def straight_length(inset)
      size = size_at(inset)
      (@long_x ? size[0] : size[1]) - 2.0 * radius_at(inset)
    end

    def long_side
      @long_x ? @w : @h
    end

    def ring(inset, feature = nil)
      size = size_at(inset)
      r = radius_at(inset)
      sx = size[0] / 2.0 - r
      sy = size[1] / 2.0 - r
      fractions = []
      if feature
        ref_half = straight_length(feature.ref_inset) / 2.0
        fractions = feature.breaks.map { |s| s / ref_half }
      end
      pts = []
      tags = []
      add_corner(pts, 0, sx, -sy, r)
      add_side(pts, tags, fractions, sx, sy, r, 1)
      add_corner(pts, 1, sx, sy, r)
      add_side(pts, tags, fractions, sx, sy, r, 2)
      add_corner(pts, 2, -sx, sy, r)
      add_side(pts, tags, fractions, sx, sy, r, 3)
      add_corner(pts, 3, -sx, -sy, r)
      add_side(pts, tags, fractions, sx, sy, r, 0)
      Ring.new(pts, tags)
    end

    private

    def add_corner(pts, quadrant, cx, cy, r)
      start = CORNER_STARTS[quadrant]
      ux = start[0]
      uy = start[1]
      j = 0
      while j <= @corner_segs
        if j == @corner_segs
          c = 0.0
          s = 1.0
        else
          t = j * Math::PI / 2.0 / @corner_segs
          c = Math.cos(t)
          s = Math.sin(t)
        end
        pts << [cx + r * (ux * c - uy * s), cy + r * (uy * c + ux * s)]
        j += 1
      end
    end

    # side: 0 bottom, 1 right, 2 top, 3 left. Vertices on one side share their
    # fixed coordinate exactly, which keeps them exactly collinear for earcut.
    def add_side(pts, tags, fractions, sx, sy, r, side)
      horizontal = side == 0 || side == 2
      return if fractions.empty? || horizontal != @long_x
      ordered = side == 0 || side == 1 ? fractions : fractions.reverse
      ordered.each do |f|
        case side
        when 0
          x = f * sx
          tags << [pts.size, 0.0, -1.0, f * sx]
          pts << [x, -sy + r * -1.0]
        when 1
          tags << [pts.size, 1.0, 0.0, f * sy]
          pts << [sx + r, f * sy]
        when 2
          tags << [pts.size, 0.0, 1.0, f * sx]
          pts << [f * sx, sy + r]
        else
          tags << [pts.size, -1.0, 0.0, f * sy]
          pts << [-sx + r * -1.0, f * sy]
        end
      end
    end
  end

  class CircleOutline
    attr_reader :diameter

    def initialize(diameter, segs)
      @diameter = diameter
      @segs = segs
    end

    def radius_at(inset)
      @diameter / 2.0 - inset
    end

    def ring(inset, feature = nil)
      r = radius_at(inset)
      angles = feature ? angles_for(feature) : uniform_angles
      pts = angles.map { |a| [r * Math.cos(a), r * Math.sin(a)] }
      tags = []
      if feature
        ref_r = radius_at(feature.ref_inset)
        half = feature.length / 2.0
        angles.each_with_index do |a, i|
          k = (a / (Math::PI / 2.0)).round
          s = (a - k * Math::PI / 2.0) * ref_r
          tags << [i, Math.cos(a), Math.sin(a), s] if s.abs <= half + 1e-9
        end
      end
      Ring.new(pts, tags)
    end

    private

    # Starts at -45 degrees so that no feature window wraps around.
    def uniform_angles
      list = []
      i = 0
      while i < @segs
        list << -Math::PI / 4.0 + i * 2.0 * Math::PI / @segs
        i += 1
      end
      list
    end

    def angles_for(feature)
      ref_r = radius_at(feature.ref_inset)
      step = 2.0 * Math::PI / @segs
      half = feature.length / 2.0 / ref_r
      cap = (feature.length / 2.0 - feature.end_radius) / ref_r
      breaks = feature.breaks.map { |s| s / ref_r }
      kept = uniform_angles.reject do |a|
        k = (a / (Math::PI / 2.0)).round
        d = (a - k * Math::PI / 2.0).abs
        d >= cap - step * 0.25 && d <= half + step * 0.25
      end
      extra = []
      k = 0
      while k < 4
        breaks.each { |b| extra << k * Math::PI / 2.0 + b }
        k += 1
      end
      (kept + extra).sort
    end
  end

  def self.circle_points(cx, cy, r, segs)
    list = []
    i = 0
    while i < segs
      a = i * 2.0 * Math::PI / segs
      list << [cx + r * Math.cos(a), cy + r * Math.sin(a)]
      i += 1
    end
    list
  end
end
