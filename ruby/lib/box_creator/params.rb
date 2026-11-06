# Input parsing and defaults. Parameters travel as "key=value" lines so that
# the wasm build needs no JSON dependency.
module BoxCreator
  class ValidationError < StandardError
    attr_reader :problems

    # problems: array of [field key, message]
    def initialize(problems)
      super('invalid parameters')
      @problems = problems
    end
  end

  module Params
    DEFAULTS = {
      'shape' => 'rect', 'w' => 70.0, 'd' => 58.0, 'h' => 100.0, 'r_out' => 5.0, 'dia' => 60.0,
      'split' => 'lid', 'split_h' => 33.0,
      'content' => 'hollow', 'hole_d' => 16.0, 'hole_n' => 2.0, 'hole_depth' => 20.0,
      'lid_wall' => 2.0, 'lid_topwall' => 2.0, 'fit' => 0.2, 'lip_h' => 8.0, 'lip_chamf' => 0.8,
      'mouth_chamf' => 0.6, 'r_top' => 1.5, 'base_wall' => 2.0,
      'floor_hollow' => 2.0, 'floor_holes' => 3.0,
      'hole_clear' => 1.0, 'hole_chamf' => 1.0, 'min_wall' => 3.0,
      'bump' => 0.5, 'bump_r' => 1.2, 'groove_depth' => 0.6, 'groove_r' => 1.35,
      'rib_pct' => 45.0, 'rib_arc' => 15.0, 'segs' => 128.0
    }.freeze

    TEXT_KEYS = %w[shape split content].freeze

    def self.parse(text)
      values = {}
      DEFAULTS.each { |k, v| values[k] = v }
      text.split("\n").each do |line|
        eq = line.index('=')
        next if eq.nil?
        key = line[0, eq].strip
        value = line[(eq + 1)..-1].to_s.strip
        next unless DEFAULTS.key?(key)
        values[key] = TEXT_KEYS.include?(key) ? value : value.to_f
      end
      values
    end
  end
end
