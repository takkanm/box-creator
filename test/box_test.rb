require 'minitest/autorun'
require_relative '../ruby/box_creator'
require_relative 'support'

class BoxTest < Minitest::Test
  # Inputs are inside dimensions. Outer sizes in the comments.
  CASE1 = 'shape=rect w=61.6 d=49.6 h=96 split=lid split_h=33 content=hollow'.freeze # 70 x 58 x 100
  CASE2 = 'shape=rect w=46 d=25 h=64 split=base split_h=25 content=holes hole_d=16 hole_n=2 hole_depth=30'.freeze # 50 x 29 x 69
  CYL_HOLLOW = 'shape=cyl dia=51.6 h=96 split=lid split_h=33 content=hollow'.freeze # D60 x 100
  CYL_HOLES = 'shape=cyl dia=76 h=85 split=lid split_h=30 content=holes hole_d=16 hole_n=5 hole_depth=30'.freeze # D80 x 90
  TALL = 'shape=rect w=54 d=66 h=95 split=lid split_h=33 content=holes hole_d=12 hole_n=6 hole_depth=30'.freeze # 58 x 70 x 100

  # Rewrites a spec written with outer sizes into inside dimensions.
  def from_outer(spec)
    holes = spec.include?('content=holes')
    side = holes ? 2.0 : 4.2
    floor = holes ? 3.0 : 2.0
    spec.gsub(/\b(w|d|dia|h)=([\d.]+)/) do
      key = Regexp.last_match(1)
      value = Regexp.last_match(2).to_f
      "#{key}=#{(key == 'h' ? value - floor - 2.0 : value - 2.0 * side).round(3)}"
    end
  end

  def text(spec)
    spec.split.join("\n")
  end

  def stl(spec, part)
    out = BoxCreator.generate(text(spec), part)
    raise out if out.start_with?('!ERR')
    StlMesh.new(out)
  end

  def info(spec)
    out = BoxCreator.generate(text(spec), BoxCreator::PART_INFO)
    assert out.start_with?('INFO'), out
    out.lines.drop(1).map { |l| l.chomp.split('=', 2) }.to_h
  end

  def errors(spec)
    out = BoxCreator.generate(text(spec), BoxCreator::PART_INFO)
    assert out.start_with?('!ERR'), "expected an error, got #{out}"
    out.lines.drop(1).map { |l| l.chomp.split("\t", 2) }.to_h
  end

  def assert_solid(mesh, label)
    assert_empty mesh.edge_defects.first(5), "#{label}: not 2-manifold"
    assert_equal 0, mesh.degenerate_count, "#{label}: degenerate triangles"
    assert_equal 0, mesh.normal_mismatches, "#{label}: normals disagree with winding"
    assert_operator mesh.volume, :>, 0, "#{label}: volume"
  end

  def assert_bounds(mesh, expected, label)
    mesh.bounds.zip(expected).each do |(lo, hi), (elo, ehi)|
      assert_in_delta elo, lo, 1e-3, label
      assert_in_delta ehi, hi, 1e-3, label
    end
  end

  # --- every part of every reference case ---------------------------------

  def test_reference_cases_are_watertight_without_self_intersection
    [CASE1, CASE2, CYL_HOLLOW, CYL_HOLES, TALL].each do |spec|
      [0, 1, 2].each do |part|
        mesh = stl(spec, part)
        assert_solid mesh, "#{spec} part #{part}"
        assert_empty mesh.self_intersections.first(3), "#{spec} part #{part}: self-intersection"
      end
    end
  end

  def test_parameter_sweep_is_watertight
    specs = []
    %w[0.5 1 2.2 5 12].each { |r| specs << "w=40 d=30 h=50 r_out=#{r}" }
    %w[0 0.8 3].each { |r| specs << "w=40 d=30 h=50 r_top=#{r}" }
    specs << 'w=40 d=30 h=50 lip_chamf=0 mouth_chamf=0 r_top=0'
    specs << 'w=30 d=30 h=40 split=base split_h=15'
    specs << 'w=20 d=14 h=40 split=lid split_h=11 r_out=1'
    specs << 'w=200 d=20 h=30 split=lid split_h=12'
    (1..12).each { |n| specs << "w=120 d=80 h=60 content=holes hole_d=10 hole_n=#{n} hole_depth=15" }
    (1..7).each { |n| specs << "shape=cyl dia=90 h=60 content=holes hole_d=12 hole_n=#{n} hole_depth=15" }
    specs << 'content=holes hole_d=20 hole_n=1 hole_chamf=0'
    specs << 'shape=cyl dia=12 h=30 split=lid split_h=11'
    specs << 'shape=cyl dia=25 h=30 split=lid split_h=11 segs=96'
    [32, 96, 100, 128].each { |s| specs << "w=70 d=58 h=100 segs=#{s}" }
    specs.map { |spec| from_outer(spec) }.each do |spec|
      [0, 1, 2].each { |part| assert_solid stl(spec, part), "#{spec} part #{part}" }
    end
  end

  # --- case 1: W70 x D58 x H100, lid 33 -----------------------------------

  def test_case1_dimensions
    base = stl(CASE1, 0)
    lid = stl(CASE1, 1)
    ring = stl(CASE1, 2)
    bump = 0.5
    assert_bounds base, [[-35, 35], [-29, 29], [0, 75]], 'base'
    assert_bounds lid, [[-35, 35], [-29, 29], [0, 33]], 'lid'
    assert_bounds ring, [[-35, 35], [-29, 29], [0, 10]], 'ring'

    i = info(CASE1)
    assert_equal '100', i['h']
    assert_equal '70 × 58', i['outer_size']
    assert_equal '67', i['base_h']
    assert_equal '75', i['top_z']
    assert_equal '61.6 × 49.6', i['base_inner']
    assert_equal '73', i['base_depth']
    assert_equal '66 × 54', i['lid_inner']

    below = base.slice(30.01)
    assert_in_delta 30.8, Section.ray_hits(below, 0).first, 1e-3
    assert_in_delta 24.8, Section.ray_hits(below, 1).first, 1e-3
    assert_in_delta 35.0, Section.ray_hits(below, 0).last, 1e-3
    assert Section.inside?(base.slice(1.9), 0, 0), 'floor is solid'
    refute Section.inside?(base.slice(2.1), 0, 0), 'cavity starts at the floor'

    lip = base.slice(70.01)
    assert_in_delta 32.8, Section.ray_hits(lip, 0).last, 1e-3
    # rib on the long sides only: the tip sticks out of the y faces at the lip centre
    centre = base.slice(71.001)
    assert_in_delta 26.8 + bump, Section.ray_hits(centre, 1).last, 1e-3
    assert_in_delta 32.8, Section.ray_hits(centre, 0).last, 1e-3

    open = lid.unflipped(100)
    assert_in_delta 33.0, Section.ray_hits(open.slice(90.01), 0).first, 1e-3
    assert_in_delta 27.0, Section.ray_hits(open.slice(90.01), 1).first, 1e-3
    assert_in_delta 27.6, Section.ray_hits(open.slice(71.001), 1).first, 1e-3 # groove
  end

  def test_case1_volume_matches_analytic_value
    rr = ->(w, h, r) { w * h - (4 - Math::PI) * r * r }
    outer = rr.(70, 58, 5)
    lip = rr.(65.6, 53.6, 2.8)
    cavity = rr.(61.6, 49.6, 0.8)
    expected = outer * 67 + lip * 8 - cavity * 73
    assert_in_delta 1.0, stl(CASE1, 0).volume / expected, 0.002
    perimeter = 2 * (70 + 58) - (8 - 2 * Math::PI) * 5
    top_round = (1 - Math::PI / 4) * 1.5**2 * perimeter
    mouth_chamfer = 0.6**2 / 2 * perimeter
    r = 1.35
    depth = 0.6
    groove_section = r * r * Math.acos((r - depth) / r) - (r - depth) * Math.sqrt(2 * r * depth - depth * depth)
    grooves = 2 * groove_section * 32.5
    lid_expected = outer * 33 - rr.(66, 54, 3) * 31 - top_round - mouth_chamfer - grooves
    assert_in_delta 1.0, stl(CASE1, 1).volume / lid_expected, 0.002
  end

  # --- case 2: W50 x D29 x H69, holes ------------------------------------

  def test_case2_dimensions_and_layout
    i = info(CASE2)
    assert_equal '69', i['h']
    assert_equal '50 × 29', i['outer_size']
    assert_equal '46 × 25', i['lid_inner']
    assert_equal '25', i['base_h']
    assert_equal '33', i['top_z']
    assert_equal '17', i['hole_dia']
    assert_equal '21', i['hole_pitch']
    assert_equal '1x2', i['hole_grid']
    assert_equal '3', i['hole_bottom']
    assert_equal '-10.5,0;10.5,0', i['hole_points']

    base = stl(CASE2, 0)
    assert_bounds base, [[-25, 25], [-14.5, 14.5], [0, 33]], 'base'
    section = base.slice(15.01)
    assert Section.inside?(section, 0, 0), 'material between the holes'
    refute Section.inside?(section, 10.5, 0), 'hole'
    assert_in_delta 2.0, Section.ray_hits(section, 0).first, 1e-2 # 10.5 - 8.5
    assert_in_delta 19.0, Section.ray_hits(section, 0)[1], 1e-2
    assert Section.inside?(base.slice(2.9), 10.5, 0), 'floor under the hole'
    refute Section.inside?(base.slice(3.1), 10.5, 0), 'hole reaches the floor'
  end

  def test_hole_depth_limit
    assert_includes errors(CASE2.sub('hole_depth=30', 'hole_depth=30.5'))['hole_depth'], '30'
  end

  # --- inside dimensions -----------------------------------------------------

  def test_hollow_inputs_are_the_base_cavity
    spec = 'w=40 d=30 h=50 split=lid split_h=20'
    base = stl(spec, 0)
    assert_bounds base, [[-24.2, 24.2], [-19.2, 19.2], [0, 54 - 20 + 8]], 'outer size'
    section = base.slice(10.01)
    assert_in_delta 20.0, Section.ray_hits(section, 0).first, 1e-3
    assert_in_delta 15.0, Section.ray_hits(section, 1).first, 1e-3
  end

  def test_hollow_cylinder_input_is_the_base_cavity
    section = stl('shape=cyl dia=40 h=50 split=lid split_h=20', 0).slice(10.01)
    assert_in_delta 20.0, Section.ray_hits(section, 0).first, 1e-3
    assert_in_delta 24.2, Section.ray_hits(section, 0).last, 1e-3
  end

  def test_hole_inputs_are_the_lid_interior
    spec = 'w=60 d=40 h=50 split=lid split_h=20 content=holes hole_d=10 hole_n=2'
    i = info(spec)
    assert_equal '60 × 40', i['lid_inner']
    assert_equal '64 × 44', i['outer_size']
    section = stl('shape=cyl dia=60 h=50 split=lid split_h=20 content=holes hole_d=10 hole_n=2', 1)
              .unflipped(55).slice(50.01)
    assert_in_delta 30.0, Section.ray_hits(section, 0).first, 1e-3
  end

  def test_height_is_from_floor_to_lid_ceiling
    [['h=50 split=lid split_h=20', 2.0], ['h=50 split=lid split_h=20 content=holes hole_d=10 hole_n=1', 3.0]].each do |spec, floor|
      i = info(spec)
      total = i['h'].to_f
      assert_in_delta 50 + floor + 2.0, total, 1e-9
      lid = stl(spec, 1).unflipped(total)
      assert Section.inside?(lid.slice(total - 1.9), 0, 0), 'lid top is solid'
      refute Section.inside?(lid.slice(total - 2.1), 0, 0), 'ceiling is 2 below the top'
    end
  end

  # --- assembled fit --------------------------------------------------------

  def assembled(spec)
    i = info(spec)
    h = i['h'].to_f
    [stl(spec, 0), stl(spec, 1).unflipped(h), i['base_h'].to_f, i['top_z'].to_f, h]
  end

  def section_levels(base_h, top_z)
    centre = (base_h + top_z) / 2.0
    offsets = [-1.2, -0.97, -0.7, -0.4, -0.1, 0.03, 0.2, 0.5, 0.9, 1.1]
    offsets.map { |o| centre + o } + [base_h + 0.03, base_h + 0.3, base_h + 0.7, top_z - 0.3, top_z - 0.03]
  end

  def test_lid_and_base_do_not_overlap_when_assembled
    [CASE1, CASE2, CYL_HOLLOW, CYL_HOLES, TALL].each do |spec|
      base, lid, base_h, top_z, = assembled(spec)
      section_levels(base_h, top_z).each do |z|
        b = base.slice(z)
        l = lid.slice(z)
        refute_empty b
        refute_empty l
        points = b.flatten(1)
        assert points.none? { |x, y| Section.inside?(l, x, y) }, "#{spec}: base enters lid material at z=#{z}"
        assert_operator Section.gap(points, l), :>=, 0.19, "#{spec}: clearance at z=#{z}"
      end
    end
  end

  def test_rib_engages_groove
    [CASE1, CYL_HOLLOW].each do |spec|
      base, lid, base_h, top_z, = assembled(spec)
      z = (base_h + top_z) / 2.0 + 0.001
      rib_tip = Section.ray_hits(base.slice(z), 1).last
      lid_wall = Section.ray_hits(lid.slice(base_h + 7.5), 1).first
      groove = Section.ray_hits(lid.slice(z), 1).first
      assert_in_delta 0.3, rib_tip - lid_wall, 1e-3, 'BUMP - FIT'
      assert_in_delta 0.3, groove - rib_tip, 1e-3, 'clearance inside the groove'
    end
  end

  def test_stored_cylinders_clear_the_lid
    [[CASE2, 8.0], [CYL_HOLES, 8.0], [TALL, 6.0]].each do |spec, radius|
      i = info(spec)
      _, lid, base_h, = assembled(spec)
      centres = i['hole_points'].split(';').map { |s| s.split(',').map(&:to_f) }
      h = i['h'].to_f
      [base_h + 0.5, base_h + 4.003, h - 2.5].each do |z|
        l = lid.slice(z)
        centres.each do |c|
          refute Section.inside?(l, c[0], c[1]), "#{spec}: cylinder centre inside the lid wall at z=#{z}"
          assert_operator Section.gap([c], l), :>=, radius, "#{spec}: cylinder touches the lid at z=#{z}"
        end
      end
    end
  end

  # --- layout ---------------------------------------------------------------

  def test_rect_layout_runs_along_the_long_side
    wide = info(from_outer('w=120 d=40 h=60 content=holes hole_d=10 hole_n=3 hole_depth=15'))
    assert_equal '1x3', wide['hole_grid']
    assert wide['hole_points'].split(';').all? { |q| q.split(',')[1].to_f.zero? }
    narrow = info(from_outer('w=40 d=120 h=60 content=holes hole_d=10 hole_n=3 hole_depth=15'))
    assert narrow['hole_points'].split(';').all? { |q| q.split(',')[0].to_f.zero? }
  end

  def test_rect_layout_uses_rows_when_needed
    assert_equal '2x2', info(from_outer('w=70 d=58 h=60 content=holes hole_d=16 hole_n=4 hole_depth=15'))['hole_grid']
    assert_equal '2x3', info(from_outer('w=90 d=60 h=60 content=holes hole_d=16 hole_n=5 hole_depth=15'))['hole_grid']
  end

  def test_circle_layout
    one = info(from_outer('shape=cyl dia=60 h=60 content=holes hole_d=16 hole_n=1 hole_depth=15'))
    assert_equal '0,0', one['hole_points']
    four = info(from_outer('shape=cyl dia=80 h=60 content=holes hole_d=12 hole_n=4 hole_depth=15'))
    radii = four['hole_points'].split(';').map { |q| Math.hypot(*q.split(',').map(&:to_f)) }
    assert_operator radii.max - radii.min, :<, 0.02
  end

  def test_all_layouts_respect_min_wall
    specs = (1..12).map { |n| "w=120 d=80 h=60 content=holes hole_d=10 hole_n=#{n} hole_depth=15" }
    specs += (1..7).map { |n| "shape=cyl dia=90 h=60 content=holes hole_d=12 hole_n=#{n} hole_depth=15" }
    specs.map { |spec| from_outer(spec) }.each do |spec|
      model = BoxCreator::Model.new(BoxCreator::Params.parse(text(spec)))
      pts = model.layout[:points]
      d = model.hole_diameter
      pts.combination(2).each do |a, b|
        assert_operator Math.hypot(a[0] - b[0], a[1] - b[1]), :>=, d + 3.0 - 1e-6, spec
      end
      section = StlMesh.new(model.build_base.to_stl('t')).slice(model.top_z - 2.0)
      outer = section.reject do |seg|
        pts.any? { |c| Math.hypot(seg[0][0] - c[0], seg[0][1] - c[1]) < d / 2.0 + 0.1 }
      end
      pts.each do |c|
        assert_operator Section.gap([c], outer) - d / 2.0, :>=, 3.0 - 1e-3, "#{spec}: wall to the lip"
      end
    end
  end

  # --- validation -----------------------------------------------------------

  def test_too_many_holes_names_the_fix
    message = errors('w=46 d=25 h=64 content=holes hole_d=16 hole_n=5 hole_depth=20')['hole_n']
    assert_includes message, '個数を 2 個以下'
    assert_includes message, '円筒の直径'
    assert_includes message, '幅 W'
  end

  def test_too_many_holes_in_a_cylinder_names_the_fix
    message = errors('shape=cyl dia=36 h=60 content=holes hole_d=16 hole_n=4 hole_depth=15')['hole_n']
    assert_includes message, '内径を'
  end

  def test_suggested_fixes_actually_fit
    message = errors('w=46 d=25 h=64 content=holes hole_d=16 hole_n=3 hole_depth=20')['hole_n']
    width = message[/幅 W を ([\d.]+)/, 1]
    diameter = message[/円筒の直径を ([\d.]+)/, 1]
    assert info("w=#{width} d=25 h=64 content=holes hole_d=16 hole_n=3 hole_depth=20")
    assert info("w=46 d=25 h=64 content=holes hole_d=#{diameter} hole_n=3 hole_depth=20")
  end

  def test_absurd_hole_counts_are_rejected_quickly
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert errors('content=holes hole_n=100000').key?('hole_n')
    message = errors('w=46 d=25 h=64 content=holes hole_d=16 hole_n=200 hole_depth=20')['hole_n']
    assert_includes message, '個数を 2 個以下'
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2.0
  end

  def test_height_split_limits
    assert errors('h=100 split=lid split_h=5').key?('split_h')
    assert errors('h=100 split=base split_h=95').key?('split_h')
    assert errors('h=2').key?('h')
  end

  def test_bad_values_are_reported_per_field
    assert errors('w=0').key?('w')
    assert errors('w=1 d=58').key?('w')
    assert errors('shape=cyl dia=1').key?('dia')
    assert errors('mouth_chamf=3').key?('mouth_chamf')
    assert errors('content=holes hole_n=1.5').key?('hole_n')
    assert errors('segs=4').key?('segs')
  end

  def test_split_by_base_height_equals_split_by_lid_height
    a = BoxCreator.generate(text('h=96 split=lid split_h=33'), 0)
    b = BoxCreator.generate(text('h=96 split=base split_h=67'), 0)
    assert_equal a, b
  end
end
