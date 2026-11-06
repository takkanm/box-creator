require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../ruby/box_creator'
require_relative 'support'

# Checks that docs/box.wasm produces the same parts as CRuby. Rebuild first with
# scripts/build_wasm.sh. libm differs slightly between platforms, so vertices are
# compared with a tolerance rather than byte for byte.
class WasmTest < Minitest::Test
  CASES = {
    'case1' => 'shape=rect w=61.6 d=49.6 h=96 split=lid split_h=33 content=hollow',
    'case2' => 'shape=rect w=46 d=25 h=64 split=base split_h=25 content=holes hole_d=16 hole_n=2 hole_depth=30',
    'cyl' => 'shape=cyl dia=51.6 h=96 split=lid split_h=33 content=hollow',
    'cylholes' => 'shape=cyl dia=76 h=85 split=lid split_h=30 content=holes hole_d=16 hole_n=5 hole_depth=30',
    'grid12' => 'w=120 d=80 h=60 content=holes hole_d=10 hole_n=12 hole_depth=15',
    'grid40' => 'w=180 d=120 h=60 content=holes hole_d=8 hole_n=40 hole_depth=15 segs=128'
  }.freeze

  def run_wasm(lines)
    Dir.mktmpdir do |dir|
      script = File.expand_path('wasm_cli.mjs', __dir__)
      out, status = Open3.capture2e('node', script, dir, stdin_data: lines.join("\n"))
      assert status.success?, out
      puts out if ENV['VERBOSE']
      yield dir
    end
  end

  def test_parts_match_cruby
    lines = CASES.flat_map { |name, spec| (0..3).map { |part| "#{name}-#{part}|#{part}|#{spec}" } }
    run_wasm(lines) do |dir|
      CASES.each do |name, spec|
        text = spec.split.join("\n")
        assert_equal BoxCreator.generate(text, 3), File.binread("#{dir}/#{name}-3.bin").force_encoding('UTF-8')
        (0..2).each do |part|
          wasm = File.binread("#{dir}/#{name}-#{part}.bin")
          ruby = BoxCreator.generate(text, part)
          assert_equal ruby.bytesize, wasm.bytesize, "#{name} part #{part}"
          count = (wasm.bytesize - 84) / 50
          a = wasm.byteslice(84..).unpack('e12 x2' * count)
          b = ruby.byteslice(84..).unpack('e12 x2' * count)
          worst = a.zip(b).map { |x, y| (x - y).abs }.max
          assert_operator worst, :<, 1e-3, "#{name} part #{part}"
          mesh = StlMesh.new(wasm)
          assert_empty mesh.edge_defects.first(5), "#{name} part #{part}"
          assert_operator mesh.volume, :>, 0
        end
      end
    end
  end

  def test_validation_errors_cross_the_boundary
    run_wasm(['err|3|w=46 d=25 h=64 content=holes hole_d=16 hole_n=5 hole_depth=20']) do |dir|
      out = File.binread("#{dir}/err.bin").force_encoding('UTF-8')
      assert out.start_with?("!ERR\nhole_n\t"), out
      assert_includes out, '個数を 2 個以下'
    end
  end
end
