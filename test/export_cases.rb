# Writes the reference cases as STL. Usage: ruby test/export_cases.rb <dir>
require_relative '../ruby/box_creator'

CASES = {
  'case1' => 'shape=rect w=61.6 d=49.6 h=96 split=lid split_h=33 content=hollow',
  'case2' => 'shape=rect w=46 d=25 h=64 split=base split_h=25 content=holes hole_d=16 hole_n=2 hole_depth=30',
  'cyl' => 'shape=cyl dia=51.6 h=96 split=lid split_h=33 content=hollow',
  'cylholes' => 'shape=cyl dia=76 h=85 split=lid split_h=30 content=holes hole_d=16 hole_n=5 hole_depth=30',
  'tall' => 'shape=rect w=54 d=66 h=95 split=lid split_h=33 content=holes hole_d=12 hole_n=6 hole_depth=30',
  'screw' => 'shape=cyl dia=51.6 h=96 split=lid split_h=33 content=hollow closure=screw',
  'screwholes' => 'shape=cyl dia=70 h=85 split=lid split_h=30 content=holes hole_d=16 hole_n=5 hole_depth=30 closure=screw'
}.freeze

dir = ARGV.fetch(0)
CASES.each do |name, spec|
  text = spec.split.join("\n")
  { 'base' => 0, 'lid' => 1, 'ring' => 2 }.each do |part, id|
    File.binwrite(File.join(dir, "#{name}_#{part}.stl"), BoxCreator.generate(text, id))
  end
  total = BoxCreator::Model.new(BoxCreator::Params.parse(text)).total_h
  File.write(File.join(dir, "#{name}.h"), total.to_s)
  File.write(File.join(dir, "#{name}.pitch"), '3.0') if spec.include?('closure=screw')
end
