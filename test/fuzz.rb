# Random valid parameters must always give a clean mesh. Usage: SEED=1 ruby test/fuzz.rb
require_relative '../ruby/box_creator'
require_relative 'support'
rng = Random.new((ENV["SEED"]||20261106).to_i)
ok = rejected = 0
bad = []
t0 = Time.now
1500.times do
  cyl = rng.rand < 0.4
  holes = rng.rand < 0.6
  w = (rng.rand(15.0..160.0) * 2).round / 2.0
  d = (rng.rand(15.0..160.0) * 2).round / 2.0
  spec = { 'shape' => cyl ? 'cyl' : 'rect', 'w' => w, 'd' => d, 'dia' => w,
           'h' => rng.rand(20.0..120.0).round(1), 'r_out' => rng.rand(0.5..12.0).round(2),
           'split' => 'lid', 'split_h' => rng.rand(11.0..40.0).round(1),
           'content' => holes ? 'holes' : 'hollow', 'hole_d' => rng.rand(3.0..30.0).round(1),
           'hole_n' => rng.rand(1..14), 'hole_depth' => rng.rand(3.0..20.0).round(1),
           'segs' => [16, 32, 48, 64, 96].sample(random: rng), 'fit' => rng.rand(0.1..0.4).round(2),
           'r_top' => rng.rand(0.0..2.0).round(2), 'lip_chamf' => rng.rand(0.0..1.0).round(2) }
  text = spec.map { |k, v| "#{k}=#{v}" }.join("\n")
  begin
    info = BoxCreator.generate(text, 3)
    if info.start_with?('!ERR') then rejected += 1; next end
    (0..2).each do |part|
      m = StlMesh.new(BoxCreator.generate(text, part))
      defects = m.edge_defects.size
      degen = m.degenerate_count
      bad << [spec, part, defects, degen, m.volume] if defects > 0 || degen > 0 || m.volume <= 0 || m.normal_mismatches > 0
    end
    ok += 1
  rescue => e
    bad << [spec, e.class, e.message]
  end
end
abort "failed: #{bad.first(3).inspect}" unless bad.empty?
puts "ok=#{ok} rejected=#{rejected} bad=#{bad.size} in #{(Time.now-t0).round}s"
