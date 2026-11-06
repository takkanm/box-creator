# Automatic correction: moves dependent values back into range.
#
# Model states how to clear each problem it can fix. Only those fixes are used,
# so the inside dimensions and the hole size and count are never changed, and
# the field the user is editing stays as typed.
module BoxCreator
  module Adjust
    MAX_PASSES = 24

    # Returns the changed values as { key => value }.
    def self.run(text)
      original = Params.parse(text)
      values = {}
      original.each { |k, v| values[k] = v }
      locked = Params.edited(text)
      MAX_PASSES.times do
        fix = next_fix(values, locked)
        break if fix.nil?
        values[fix[0]] = (fix[1] * 1000.0).round / 1000.0
      end
      changes = {}
      values.each { |k, v| changes[k] = v if v != original[k] }
      changes
    end

    # Only the first problem counts: later ones may exist because of it, so
    # fixing them first, or while it stands, would change values needlessly.
    def self.next_fix(values, locked)
      Model.new(values)
      nil
    rescue ValidationError => e
      e.problems[0][2].find { |fix| fix[0] != locked && fix[1] != values[fix[0]] }
    end

    def self.report(text)
      lines = ['ADJUST']
      run(text).each do |key, value|
        lines << "#{key}=#{value == value.to_i ? value.to_i : value}"
      end
      lines.join("\n")
    end
  end
end
