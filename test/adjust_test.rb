require 'minitest/autorun'
require_relative '../ruby/box_creator'

class AdjustTest < Minitest::Test
  FIXED = %w[w d dia h hole_d hole_n].freeze
  HOLES = 'content=holes hole_d=16 hole_n=2 hole_depth=20'.freeze
  SCREW = 'shape=cyl closure=screw'.freeze

  def adjust(spec)
    out = BoxCreator.generate(spec.split.join("\n"), BoxCreator::PART_ADJUST)
    assert out.start_with?('ADJUST'), out
    out.lines.drop(1).map { |l| l.chomp.split('=', 2) }.to_h.transform_values(&:to_f)
  end

  def corrected(spec)
    (spec.split + adjust(spec).map { |k, v| "#{k}=#{v}" }).join("\n")
  end

  def assert_valid_after(spec)
    info = BoxCreator.generate(corrected(spec), BoxCreator::PART_INFO)
    assert info.start_with?('INFO'), "#{spec}: #{info}"
  end

  def test_a_valid_box_is_left_alone
    assert_empty adjust('')
    assert_empty adjust("#{SCREW} #{HOLES.sub('hole_n=2', 'hole_n=1')} dia=60")
  end

  def test_chamfer_follows_a_thinner_wall
    assert_equal({ 'lip_chamf' => 0.4 }, adjust('base_wall=0.5 edited=base_wall'))
    assert_equal({ 'mouth_chamf' => 0.4, 'groove_depth' => 0.4 }, adjust('lid_wall=0.5 edited=lid_wall').slice('mouth_chamf', 'groove_depth'))
    assert_valid_after('base_wall=0.5 edited=base_wall')
    assert_valid_after('lid_wall=0.5 edited=lid_wall')
  end

  def test_corner_radius_follows_a_smaller_box
    assert_equal({ 'r_out' => 5.6 }, adjust('w=3 d=3 r_out=8 edited=w'))
    assert_valid_after('w=3 d=3 r_out=8 edited=w')
  end

  def test_split_height_moves_into_range
    assert_equal({ 'split_h' => 10.2 }, adjust('split_h=2 edited=h'))
    assert_operator adjust('h=20 split_h=33 edited=h')['split_h'], :<, 33
    assert_valid_after('h=20 split_h=33 edited=h')
    assert_valid_after('split=base split_h=200 edited=h')
  end

  def test_lip_height_grows_for_a_larger_chamfer
    spec = 'lid_wall=5 mouth_chamf=3.5 edited=mouth_chamf'
    assert_operator adjust(spec)['lip_h'], :>, 8
    assert_valid_after(spec)
  end

  def test_paired_values_move_the_other_side
    assert_equal({ 'bump_r' => 1.5 }, adjust('bump=1.5 edited=bump').slice('bump', 'bump_r'))
    assert_equal({ 'bump' => 0.3 }, adjust('bump_r=0.3 edited=bump_r').slice('bump', 'bump_r'))
    assert_equal({ 'thread_pitch' => 4.4 }, adjust("#{SCREW} thread_depth=2 edited=thread_depth").slice('thread_pitch', 'thread_depth'))
    assert_equal({ 'thread_depth' => 0.8 }, adjust("#{SCREW} thread_pitch=2 edited=thread_pitch").slice('thread_pitch', 'thread_depth'))
  end

  def test_hole_values_follow
    deep = "#{HOLES.sub('hole_depth=20', 'hole_depth=200')} w=46 d=25 edited=h"
    assert_operator adjust(deep)['hole_depth'], :<, 200
    assert_valid_after(deep)
    assert_operator adjust("#{HOLES} w=46 d=25 hole_chamf=2 edited=hole_chamf")['min_wall'], :>, 3
  end

  def test_the_edited_field_is_never_changed
    assert_empty adjust('lip_chamf=3 edited=lip_chamf')
    assert_empty adjust('split_h=2 edited=split_h')
    assert_equal({ 'lip_chamf' => 1.9 }, adjust('lip_chamf=3 edited=w'))
  end

  def test_choices_stay_with_the_user
    assert_empty adjust("#{HOLES.sub('hole_n=2', 'hole_n=50')} w=46 d=25")
    assert_empty adjust('w=1 r_out=0.5 edited=r_out')
    assert_empty adjust('h=1 split_h=33 lip_h=8 edited=lip_h').slice('h')
  end

  def test_every_result_is_valid_or_needs_the_user
    rng = Random.new(20261107)
    keys = { 'lid_wall' => 0.3..4, 'lid_topwall' => 0.5..4, 'base_wall' => 0.3..4, 'lip_h' => 1..15, 'lip_chamf' => 0..4,
             'mouth_chamf' => 0..4, 'r_top' => 0..8, 'bump' => 0.1..3, 'bump_r' => 0.2..3, 'groove_depth' => 0.1..3,
             'groove_r' => 0.2..3, 'hole_chamf' => 0..4, 'min_wall' => 0..6, 'hole_depth' => 1..200,
             'thread_pitch' => 1..5, 'thread_depth' => 0.2..3, 'r_out' => 0.5..30, 'split_h' => 1..150 }
    fixed = 0
    stuck = []
    600.times do
      spec = { 'shape' => %w[rect cyl].sample(random: rng), 'closure' => %w[snap screw].sample(random: rng),
               'content' => %w[hollow holes].sample(random: rng), 'split' => %w[lid base].sample(random: rng),
               'w' => rng.rand(10.0..150.0).round(1), 'd' => rng.rand(10.0..150.0).round(1),
               'dia' => rng.rand(20.0..150.0).round(1), 'h' => rng.rand(20.0..120.0).round(1),
               'hole_d' => rng.rand(4.0..12.0).round(1), 'hole_n' => rng.rand(1..3) }
      keys.keys.sample(4, random: rng).each { |k| spec[k] = rng.rand(keys[k].first.to_f..keys[k].last.to_f).round(2) }
      edited = keys.keys.sample(random: rng)
      text = (spec.map { |k, v| "#{k}=#{v}" } + ["edited=#{edited}"]).join(' ')
      changes = adjust(text)
      assert_empty changes.keys & FIXED, text
      refute_includes changes.keys, edited, text
      out = BoxCreator.generate(corrected(text), BoxCreator::PART_INFO)
      fixed += 1 if out.start_with?('INFO') && !changes.empty?
      next if out.start_with?('INFO')
      first = out.lines[1].split("\t").first
      stuck << first unless (FIXED + [edited]).include?(first)
    end
    assert_operator fixed, :>, 50
    assert_empty stuck
  end
end
