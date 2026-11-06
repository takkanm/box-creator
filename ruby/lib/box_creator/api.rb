# Single entry point shared by the wasm build and the tests.
module BoxCreator
  PART_BASE = 0
  PART_LID = 1
  PART_RING = 2
  PART_INFO = 3
  PART_ADJUST = 4

  def self.build_part(model, part)
    case part
    when PART_BASE then model.build_base
    when PART_LID then model.build_lid
    when PART_RING then model.build_ring
    else raise "unknown part: #{part}"
    end
  end

  # Returns binary STL for parts 0-2, "INFO\nkey=value..." for part 3 and
  # "ADJUST\nkey=value..." with the values Adjust changed for part 4.
  # Invalid input returns "!ERR\nfield\tmessage..." rather than raising.
  def self.generate(text, part)
    return Adjust.report(text) if part == PART_ADJUST
    model = Model.new(Params.parse(text))
    return "INFO\n" + model.info_lines.join("\n") if part == PART_INFO
    build_part(model, part).to_stl('box-creator')
  rescue ValidationError => e
    "!ERR\n" + e.problems.map { |pr| "#{pr[0]}\t#{pr[1]}" }.join("\n")
  end
end
