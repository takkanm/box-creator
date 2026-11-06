# Writes the reference cases as STL. Usage: ruby test/export_cases.rb <dir>
require_relative '../ruby/box_creator'

CASES = {
  'case1' => 'shape=rect w=70 d=58 h=100 split=lid split_h=33 content=hollow',
  'case2' => 'shape=rect w=50 d=29 h=69 split=base split_h=25 content=holes hole_d=16 hole_n=2 hole_depth=30',
  'cyl' => 'shape=cyl dia=60 h=100 split=lid split_h=33 content=hollow',
  'cylholes' => 'shape=cyl dia=80 h=90 split=lid split_h=30 content=holes hole_d=16 hole_n=5 hole_depth=30',
  'tall' => 'shape=rect w=58 d=70 h=100 split=lid split_h=33 content=holes hole_d=12 hole_n=6 hole_depth=30'
}.freeze

dir = ARGV.fetch(0)
CASES.each do |name, spec|
  text = spec.split.join("\n")
  { 'base' => 0, 'lid' => 1, 'ring' => 2 }.each do |part, id|
    File.binwrite(File.join(dir, "#{name}_#{part}.stl"), BoxCreator.generate(text, id))
  end
  File.write(File.join(dir, "#{name}.h"), spec[/\bh=([\d.]+)/, 1])
end
