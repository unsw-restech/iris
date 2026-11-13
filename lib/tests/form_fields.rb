# What every form's fields hold, checked on the form as it renders, as the
# pinned fork commit reads it (form_helper.rb's header names it).
# bin/check runs this on each workflows/*/form.yml.erb:
#
#   ruby lib/tests/form_fields.rb FORM...
#
# which prints "<form>: <problem>" for each problem and exits 1 if any.
#   - A select's, radio's or checkbox's value names its default by an
#     option's label: lib/form.rb selects the option whose label is the
#     value, so a data value or a typo selects none and the browser shows
#     the first option, or ticks nothing.
#   - No script line names a checkbox or multi_select as #{:field}: the
#     colon keeps a line whose other fields are empty, but ocForm.showLine
#     drops a line naming a checkbox or multi_select with nothing chosen,
#     colon or not, so the line and every field on it go (#184).

require_relative "form_helper"

module FormFields
  LABELLED = %w[select radio checkbox].freeze

  def self.problems(form_path)
    form = FormHelper.render(form_path)
    fields = form["form"] || {}
    found = fields.flat_map do |key, f|
      next [] unless f.is_a?(Hash) && LABELLED.include?(f["widget"]) && !f["value"].nil?
      labels = Array(f["options"]).map { |o| o[0].to_s }
      Array(f["value"]).map(&:to_s).reject { |v| labels.include?(v) }
                       .map { |v| %(#{key}: value "#{v}" is no option's label) }
    end
    # Every colon name in each #{...}, a function's arguments included
    # (lib/form.rb).
    colon = form["script"].to_s.scan(/\#\{([^}]*)\}/).flatten.flat_map { |b| b.scan(/:([A-Za-z_]\w*)/).flatten }
    colon.uniq.each do |key|
      widget = FormHelper.widget(form, key)
      next unless FormHelper.choice?(widget)
      found << %(script: \#{:#{key}} names a #{widget}, whose line drops when nothing is chosen, colon or not (#184))
    end
    found.map { |p| "#{form_path}: #{p}" }
  end
end

if $PROGRAM_NAME == __FILE__
  problems = ARGV.flat_map { |f| FormFields.problems(f) }
  puts problems
  exit(problems.empty? ? 0 : 1)
end
