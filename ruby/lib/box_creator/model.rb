# The box itself: derived dimensions, validation and the three printable parts.
# All parts are built in assembled coordinates (base floor at z = 0).
module BoxCreator
  class Model
    ROUND_STEPS = 6
    RING_HEIGHT = 10.0
    GROOVE_EXTRA = 1.0 # the groove is this much longer than the rib, in total
    MIN_RIB_MARGIN = 1.0
    MIN_CAVITY = 2.0
    MAX_HOLES = 200

    attr_reader :p, :base_h, :lid_h, :top_z, :floor, :layout, :warnings

    def initialize(values)
      @p = values
      @warnings = []
      @rect = @p['shape'] != 'cyl'
      @holes = @p['content'] == 'holes'
      @segs = (@p['segs'].to_i / 4) * 4
      derive_heights
      validate
      prepare
    end

    def rect?
      @rect
    end

    def holes?
      @holes
    end

    def lip_inset
      @p['lid_wall'] + @p['fit']
    end

    def ring_height
      limit = @lid_h - (@p['lid_topwall'] > @p['r_top'] ? @p['lid_topwall'] : @p['r_top'])
      limit < RING_HEIGHT ? limit : RING_HEIGHT
    end

    def build_base
      m = Mesh.new
      base_outer = @outline.ring(0.0).pts
      bottom = m.add_ring(base_outer, 0.0)
      shoulder_outer = m.add_ring(base_outer, @base_h)
      m.wall(bottom, shoulder_outer)
      m.cap(bottom, [], false)

      rib = @rib
      lip = @outline.ring(lip_inset, rib)
      levels = [m.add_ring(lip.pts, @base_h)]
      rib.z_levels.each { |z| levels << m.add_ring(lip.displaced(rib, z), z) } if rib
      chamf = @p['lip_chamf']
      levels << m.add_ring(lip.pts, @top_z - chamf)
      if chamf > 0
        levels << m.add_ring(@outline.ring(lip_inset + chamf, rib).pts, @top_z)
      end
      m.stack(levels)
      m.cap(shoulder_outer, [levels[0]], true)
      top_outer = levels[-1]

      if @holes
        build_hole_walls(m, top_outer)
      else
        cavity = @outline.ring(lip_inset + @p['base_wall']).pts
        cavity_floor = m.add_ring(cavity, @floor)
        cavity_top = m.add_ring(cavity, @top_z)
        m.wall(cavity_floor, cavity_top, true)
        m.cap(cavity_floor, [], true)
        m.cap(top_outer, [cavity_top], true)
      end
      m
    end

    def build_lid
      m = Mesh.new
      r_top = @p['r_top']
      h = @p['h']
      base_outer = @outline.ring(0.0).pts
      levels = [m.add_ring(base_outer, @base_h), m.add_ring(base_outer, h - r_top)]
      if r_top > 0
        i = 1
        while i <= ROUND_STEPS
          t = i * Math::PI / 2.0 / ROUND_STEPS
          inset = r_top * (1.0 - Math.cos(t))
          inset = r_top if i == ROUND_STEPS
          z = i == ROUND_STEPS ? h : h - r_top + r_top * Math.sin(t)
          levels << m.add_ring(@outline.ring(inset).pts, z)
          i += 1
        end
      end
      m.stack(levels)
      m.cap(levels[-1], [], true)

      inner = lid_inner_levels(m, h - @p['lid_topwall'])
      m.cap(inner[-1], [], false)
      m.cap(levels[0], [inner[0]], false)
      m.flip_about_x(h)
    end

    # The mouth of the lid only, cut flat at ring_height.
    def build_ring
      m = Mesh.new
      cut_z = @base_h + ring_height
      base_outer = @outline.ring(0.0).pts
      outer_bottom = m.add_ring(base_outer, @base_h)
      outer_top = m.add_ring(base_outer, cut_z)
      m.wall(outer_bottom, outer_top)
      inner = lid_inner_levels(m, cut_z)
      m.cap(outer_top, [inner[-1]], true)
      m.cap(outer_bottom, [inner[0]], false)
      m.flip_about_x(cut_z)
    end

    def info_lines
      lines = []
      lines << "base_h=#{fmt(@base_h)}"
      lines << "lid_h=#{fmt(@lid_h)}"
      lines << "top_z=#{fmt(@top_z)}"
      lines << "h=#{fmt(@p['h'])}"
      lines << "floor=#{fmt(@floor)}"
      lines << "ring_h=#{fmt(ring_height)}"
      if @rect
        lid_size = @outline.size_at(@p['lid_wall'])
        lines << "lid_inner=#{fmt(lid_size[0])} × #{fmt(lid_size[1])}"
      else
        lines << "lid_inner=Ø#{fmt(@outline.radius_at(@p['lid_wall']) * 2.0)}"
      end
      if @holes
        hole_d = hole_diameter
        lines << "hole_dia=#{fmt(hole_d)}"
        lines << "hole_bottom=#{fmt(@top_z - @p['hole_depth'])}"
        lines << "hole_grid=#{@layout[:rows]}x#{@layout[:cols]}"
        lines << "hole_pitch=#{fmt(@layout[:pitch_x])}"
        lines << "hole_pitch_y=#{fmt(@layout[:pitch_y])}" if @layout[:rows] > 1
        lines << "hole_ring=#{fmt(@layout[:ring_radius])}" if @layout[:ring_radius]
        lines << "hole_points=#{@layout[:points].map { |q| "#{fmt(q[0])},#{fmt(q[1])}" }.join(';')}"
        lines << "max_cyl_len=#{fmt(@p['h'] - @p['lid_topwall'] - (@top_z - @p['hole_depth']))}"
      elsif @rect
        size = @outline.size_at(lip_inset + @p['base_wall'])
        lines << "base_inner=#{fmt(size[0])} × #{fmt(size[1])}"
        lines << "base_depth=#{fmt(@top_z - @floor)}"
      else
        lines << "base_inner=Ø#{fmt(@outline.radius_at(lip_inset + @p['base_wall']) * 2.0)}"
        lines << "base_depth=#{fmt(@top_z - @floor)}"
      end
      lines << "rib_len=#{fmt(@rib ? @rib.length : 0.0)}"
      @warnings.each { |w| lines << "warn=#{w}" }
      lines
    end

    def hole_diameter
      @p['hole_d'] + @p['hole_clear']
    end

    private

    def fmt(v)
      rounded = (v * 100.0).round / 100.0
      rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
    end

    def derive_heights
      h = @p['h']
      if @p['split'] == 'base'
        @base_h = @p['split_h']
        @lid_h = h - @base_h
      else
        @lid_h = @p['split_h']
        @base_h = h - @lid_h
      end
      @top_z = @base_h + @p['lip_h']
      @floor = @holes ? @p['floor_holes'] : @p['floor_hollow']
    end

    def lid_inner_levels(m, end_z)
      groove = @groove
      inner = @outline.ring(@p['lid_wall'], groove)
      chamf = @p['mouth_chamf']
      levels = []
      if chamf > 0
        levels << m.add_ring(@outline.ring(@p['lid_wall'] - chamf, groove).pts, @base_h)
        levels << m.add_ring(inner.pts, @base_h + chamf)
      else
        levels << m.add_ring(inner.pts, @base_h)
      end
      groove.z_levels.each { |z| levels << m.add_ring(inner.displaced(groove, z), z) } if groove
      levels << m.add_ring(inner.pts, end_z)
      m.stack(levels, true)
      levels
    end

    def build_hole_walls(m, top_outer)
      hole_r = hole_diameter / 2.0
      chamf = @p['hole_chamf']
      bottom_z = @top_z - @p['hole_depth']
      entries = []
      @layout[:points].each do |c|
        body = BoxCreator.circle_points(c[0], c[1], hole_r, @segs)
        levels = [m.add_ring(body, bottom_z), m.add_ring(body, @top_z - chamf)]
        if chamf > 0
          levels << m.add_ring(BoxCreator.circle_points(c[0], c[1], hole_r + chamf, @segs), @top_z)
        end
        m.stack(levels, true)
        m.cap(levels[0], [], true)
        entries << levels[-1]
      end
      m.cap(top_outer, entries, true)
    end

    def problem(field, message)
      @problems << [field, message]
    end

    def require_positive(keys)
      keys.each { |k| problem(k, "0 より大きい値を入力してください") unless @p[k] > 0 }
    end

    def require_non_negative(keys)
      keys.each { |k| problem(k, "0 以上の値を入力してください") if @p[k] < 0 }
    end

    def validate
      @problems = []
      p = @p
      require_positive(%w[h lid_wall lid_topwall fit lip_h base_wall bump bump_r groove_depth groove_r])
      require_non_negative(%w[lip_chamf mouth_chamf r_top hole_chamf hole_clear min_wall])
      require_positive([@holes ? 'floor_holes' : 'floor_hollow'])
      require_positive(@rect ? %w[w d] : %w[dia])
      problem('r_out', '0.5 以上の値を入力してください') if @rect && p['r_out'] < 0.5
      problem('rib_pct', '0 より大きい値を入力してください') if @rect && p['rib_pct'] <= 0
      problem('rib_arc', '0 より大きい値を入力してください') if !@rect && p['rib_arc'] <= 0
      if @segs < 16 || @segs > 512
        problem('segs', '16 から 512 の範囲で入力してください')
      end
      raise ValidationError.new(@problems) unless @problems.empty?

      validate_heights
      validate_plan
      validate_details
      raise ValidationError.new(@problems) unless @problems.empty?
    end

    def validate_heights
      p = @p
      min_lid = p['lip_h'] + p['lid_topwall'] + p['fit']
      min_base = 0.5
      unless @holes
        # the floor must stay below the rim even for a very low base
        by_floor = p['floor_hollow'] + 0.5 - p['lip_h']
        min_base = by_floor if by_floor > min_base
      end
      if @lid_h < min_lid - 1e-9 || @base_h < min_base - 1e-9
        lid_from = fmt(min_lid)
        lid_to = fmt(p['h'] - min_base)
        if p['h'] < min_lid + min_base
          problem('h', "全高は #{fmt(min_lid + min_base)} mm 以上にしてください")
        elsif p['split'] == 'base'
          problem('split_h', "下箱の高さは #{fmt(min_base)}〜#{fmt(p['h'] - min_lid)} mm の範囲にしてください")
        else
          problem('split_h', "蓋の高さは #{lid_from}〜#{lid_to} mm の範囲にしてください")
        end
      end
    end

    def validate_plan
      p = @p
      inset = lip_inset + (@holes ? 0.0 : p['base_wall'])
      if @rect
        short = p['w'] < p['d'] ? p['w'] : p['d']
        need = 2.0 * inset + MIN_CAVITY
        if short < need
          problem(p['w'] < p['d'] ? 'w' : 'd', "壁を残すには #{fmt(need)} mm 以上必要です")
        end
        limit = short / 2.0
        problem('r_out', "角の半径は #{fmt(limit)} mm 未満にしてください") if p['r_out'] >= limit
      else
        need = 2.0 * inset + MIN_CAVITY
        problem('dia', "壁を残すには #{fmt(need)} mm 以上必要です") if p['dia'] < need
      end
    end

    def validate_details
      p = @p
      if p['lip_chamf'] >= p['base_wall'] && !@holes
        problem('lip_chamf', "lip の面取りは壁の厚み #{fmt(p['base_wall'])} mm 未満にしてください")
      end
      if p['lip_chamf'] >= p['lip_h']
        problem('lip_chamf', "lip の面取りは lip の高さ未満にしてください")
      end
      if p['mouth_chamf'] >= p['lid_wall']
        problem('mouth_chamf', "開口部の面取りは蓋の壁の厚み #{fmt(p['lid_wall'])} mm 未満にしてください")
      end
      validate_top_round
      problem('bump', 'rib の半径以下にしてください') if p['bump'] > p['bump_r']
      problem('groove_depth', '溝の半径以下にしてください') if p['groove_depth'] > p['groove_r']
      if p['groove_depth'] >= p['lid_wall']
        problem('groove_depth', "溝の深さは蓋の壁の厚み #{fmt(p['lid_wall'])} mm 未満にしてください")
      end
      if p['bump'] <= p['fit']
        @warnings << 'rib の飛び出しが隙間 FIT 以下のため、はまり代がありません'
      end
      return unless @problems.empty?
      rib_end = Feature.half_chord(p['bump_r'], p['bump'])
      groove_end = Feature.half_chord(p['groove_r'], p['groove_depth'])
      room_low = p['lip_h'] / 2.0 - p['mouth_chamf']
      room_high = p['lip_h'] / 2.0 - p['lip_chamf']
      if rib_end >= room_high
        problem('lip_h', "rib が入るように lip の高さを増やしてください")
      elsif groove_end >= room_low
        problem('lip_h', "溝が入るように lip の高さを増やしてください")
      end
      validate_holes if @holes
    end

    # The rounded edge must not eat through to the corner of the lid cavity.
    def validate_top_round
      p = @p
      r = p['r_top']
      dx = r - p['lid_wall']
      dy = r - p['lid_topwall']
      too_thin = dx > 0 && dy > 0 && r - Math.sqrt(dx * dx + dy * dy) < 0.5
      short = @rect ? (p['w'] < p['d'] ? p['w'] : p['d']) : p['dia']
      if too_thin || r >= short / 2.0 - 1.0 || r >= @lid_h - p['lip_h']
        problem('r_top', '天面の丸めが大きすぎます')
      end
    end

    def validate_holes
      p = @p
      if p['hole_d'] <= 0
        problem('hole_d', '0 より大きい値を入力してください')
        return
      end
      if p['hole_n'] < 1 || p['hole_n'] != p['hole_n'].to_i
        problem('hole_n', '1 以上の整数を入力してください')
        return
      end
      if p['hole_n'] > MAX_HOLES
        problem('hole_n', "個数は #{MAX_HOLES} 個以下にしてください")
        return
      end
      max_depth = @top_z - @floor
      if p['hole_depth'] > max_depth + 1e-9
        problem('hole_depth', "穴の深さは #{fmt(max_depth)} mm 以下にしてください（下箱の上端 #{fmt(@top_z)} − 床 #{fmt(@floor)}）")
      elsif p['hole_depth'] <= p['hole_chamf']
        problem('hole_depth', "穴の深さは面取り #{fmt(p['hole_chamf'])} mm より大きくしてください")
      end
      if p['min_wall'] <= 2.0 * p['hole_chamf'] || p['min_wall'] <= p['hole_chamf'] + p['lip_chamf']
        problem('min_wall', '最小の壁厚は、面取りが重ならない値まで増やしてください')
      end
      return unless @problems.empty?
      count = p['hole_n'].to_i
      @layout = compute_layout(hole_diameter, count, p['w'], p['d'], p['dia'])
      report_no_fit(count) if @layout.nil?
    end

    def compute_layout(hole_d, count, w, d, dia)
      inset = lip_inset
      if @rect
        outline = RectOutline.new(w, d, @p['r_out'], @segs)
        size = outline.size_at(inset)
        Layout.rect(size[0], size[1], outline.radius_at(inset), hole_d, count, @p['min_wall'])
      else
        Layout.circle(dia / 2.0 - inset, hole_d, count, @p['min_wall'])
      end
    end

    # Explains which single value would make the holes fit.
    def report_no_fit(count)
      p = @p
      hole_d = hole_diameter
      fits = count - 1
      fits -= 1 while fits >= 1 && compute_layout(hole_d, fits, p['w'], p['d'], p['dia']).nil?
      cyl = p['hole_d']
      cyl -= 0.5 while cyl > 1.0 && compute_layout(cyl + p['hole_clear'], count, p['w'], p['d'], p['dia']).nil?
      fixes = []
      fixes << "個数を #{fits} 個以下" if fits >= 1
      fixes << "円筒の直径を #{fmt(cyl)} mm 以下" if cyl > 1.0
      if @rect
        long_key = p['w'] >= p['d'] ? 'w' : 'd'
        grow = p[long_key]
        limit = grow + 1000.0
        found = nil
        while grow <= limit
          grow += 1.0
          w = long_key == 'w' ? grow : p['w']
          d = long_key == 'd' ? grow : p['d']
          unless compute_layout(hole_d, count, w, d, 0.0).nil?
            found = grow
            break
          end
        end
        name = long_key == 'w' ? '幅 W ' : '奥行き D '
        fixes << "#{name}を #{fmt(found)} mm 以上" if found
      else
        grow = p['dia']
        limit = grow + 1000.0
        found = nil
        while grow <= limit
          grow += 1.0
          unless compute_layout(hole_d, count, 0.0, 0.0, grow).nil?
            found = grow
            break
          end
        end
        fixes << "外径を #{fmt(found)} mm 以上" if found
      end
      problem('hole_n', "#{count} 個の穴が入りません。#{fixes.join('、')}にしてください（穴 Ø#{fmt(hole_d)}、最小の壁厚 #{fmt(p['min_wall'])} mm）")
    end

    def prepare
      p = @p
      if @rect
        @outline = RectOutline.new(p['w'], p['d'], p['r_out'], @segs)
      else
        @outline = CircleOutline.new(p['dia'], @segs)
      end
      prepare_features
    end

    def prepare_features
      p = @p
      center_z = @base_h + p['lip_h'] / 2.0
      lid_wall = p['lid_wall']
      rib_end = Feature.half_chord(p['bump_r'], p['bump'])
      groove_end = Feature.half_chord(p['groove_r'], p['groove_depth'])
      if @rect
        wanted = p['rib_pct'] / 100.0 * @outline.long_side
        room = @outline.straight_length(lip_inset) - MIN_RIB_MARGIN
        groove_room = @outline.straight_length(lid_wall) - MIN_RIB_MARGIN - GROOVE_EXTRA
        room = groove_room if groove_room < room
      else
        wanted = p['rib_arc']
        room = 0.6 * Math::PI / 2.0 * @outline.radius_at(lip_inset)
      end
      length = wanted < room ? wanted : room
      shortest = 2.0 * (rib_end > groove_end ? rib_end : groove_end) + 0.5
      if length < shortest
        @warnings << 'rib を付ける余地がないため、rib と溝を省略しました'
        @rib = nil
        @groove = nil
        return
      end
      @warnings << "rib の長さを #{fmt(length)} mm に縮めました" if length < wanted - 1e-9
      @rib = Feature.new(length, p['bump_r'], p['bump'], center_z, lip_inset)
      @groove = Feature.new(length + GROOVE_EXTRA, p['groove_r'], p['groove_depth'], center_z, lid_wall)
    end
  end
end
