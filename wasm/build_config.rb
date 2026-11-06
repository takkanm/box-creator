# mruby build: a host build for mrbc and a wasm build with only what the
# generator needs. Both use unboxed values so floats keep full double precision,
# and lift the 1 MiB string limit because an STL with many holes is larger.
DEFINES = %w[MRB_NO_BOXING MRB_INT64 MRB_STR_LENGTH_MAX=0].freeze
GEMS = %w[mruby-math mruby-pack mruby-array-ext mruby-string-ext mruby-enum-ext].freeze

MRuby::Build.new do |conf|
  conf.toolchain
  conf.cc.defines.concat(DEFINES)
  conf.gem core: 'mruby-compiler'
  conf.gem core: 'mruby-bin-mrbc'
  conf.gem core: 'mruby-bin-mruby'
  GEMS.each { |name| conf.gem core: name }
end

MRuby::CrossBuild.new('wasm') do |conf|
  conf.toolchain :emscripten
  conf.cc.defines.concat(DEFINES)
  conf.cc.flags << '-O2'
  GEMS.each { |name| conf.gem core: name }
end
