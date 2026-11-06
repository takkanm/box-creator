# CRuby loader. The wasm build compiles the same files with mrbc, in this order.
%w[earcut outline mesh layout params model api].each do |name|
  require_relative "lib/box_creator/#{name}"
end
