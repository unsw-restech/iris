# Render a form.yml.erb the way the IRIS fork of OpenComposer does at
# c5da1b9, the commit bin/ocpull keeps the IRIS instance's and the test
# instance's checkouts on, and the dev install runs (#170), for tests and
# for submitting a job without the browser. Every workflow's form tests use
# it. Moving the checkouts to a commit that changes what follows means
# changing this helper, and this commit, with them: bin/ocpull --apply
# reads the commit from this header's second line, the one place the
# repo records it, and fails after a move to any other.
#
#   render     ERB with @apps_dir and @OC_DIR_NAME set (the GET), then YAML
#              (run.rb read_yaml); @apps_dir is the folder holding the
#              form's workflow folder unless given (nil, as on run.rb's
#              re-read at submit)
#   defaults   each field's value; a checkbox's or multi_select's chosen
#              labels become their data values, a multi_select entry that
#              is no option stays as typed (form.js getValue), joined by
#              the field's separator, or an array if it has none
#   check      eval the check: section with each field as @field, as
#              run.rb's set_check_value sets it; oc_assert and any other
#              error re-render the form with its message (run.rb rescues
#              every exception), and halt shows its message on a bare page
#   script     fill #{field}, #{:field} and #{zeropadding(f, n)}, as the
#              page's script pane does (form.js showLine): a line whose
#              plain #{field} is empty is dropped, as is one naming a
#              checkbox or multi_select with nothing chosen, #{:field} too,
#              and one naming a checkbox or multi_select with no separator
#              is written once per value; the lines are joined as the pane
#              joins them (lib/form.rb splits the script on newlines), so
#              trailing empty lines go and the last line has no newline.
#              The pane renders each line as its own segment and a field
#              change rewrites only that field's lines (#165); with the
#              pane unedited, it submits the script rendered whole
#
# Not copied: dynamic widgets (disable-, hide-, set-), so a disabled
# field still fills its lines, calc, dirname and basename, and the locked
# lines and editable region (#168, #171), which only limit edits in the
# pane and leave the submitted script as rendered.
#
# From the command line, prints the job script for the given fields:
#   ruby lib/tests/form_helper.rb [--apps-dir DIR] [--no-check] FORM \
#     dataset=/srv/scratch/$USER/x epochs=2 ...
# --no-check prints the script even if check: rejects the fields.

require "erb"
require "yaml"

module FormHelper
  class Context
    def initialize(apps_dir, dir_name)
      @apps_dir = apps_dir
      @OC_DIR_NAME = dir_name
    end

    def get_binding = binding
  end

  def self.render(form, apps_dir = File.dirname(File.dirname(File.expand_path(form))))
    workflow = File.basename(File.dirname(File.expand_path(form)))
    text = ERB.new(File.read(form), trim_mode: "-").result(Context.new(apps_dir, workflow).get_binding)
    YAML.load(text)
  end

  # Whether a field with this widget holds its chosen options' values,
  # which defaults and script treat alike.
  def self.choice?(widget) = %w[checkbox multi_select].include?(widget)

  # The values a researcher submits without touching anything but `given`.
  def self.defaults(form, given = {})
    values = {}
    form["form"].each do |key, f|
      v = f["value"]
      if choice?(f["widget"])
        # Each chosen label's data value, its label if it has none; a
        # multi_select entry that is no option stays as typed.
        chosen = Array(v).map do |label|
          o = Array(f["options"]).find { |x| x[0] == label } || [label]
          o[1].nil? ? o[0] : o[1]
        end
        values[key] = f["separator"].nil? ? chosen : chosen.join(f["separator"])
      elsif f["widget"] == "number" && v.is_a?(Array)
        v.each_with_index { |x, i| values["#{key}_#{i + 1}"] = x }
      else
        values[key] = v
      end
    end
    values.merge(given.transform_keys(&:to_s))
  end

  class Checker
    def oc_assert(cond, msg = "Error exists in script content.") = (raise RuntimeError, msg unless cond)

    # Sinatra's halt throws past run.rb's rescue to a bare error page
    # holding its body, the last argument.
    def halt(*args) = throw(:halt, args.last.to_s)

    # run.rb sets nothing for an unchecked checkbox, and one value as
    # itself (set_check_value).
    def run(code, values)
      values.each do |k, v|
        v = v.size > 1 ? v : v.first if v.is_a?(Array)
        instance_variable_set("@#{k}", v) unless v.nil?
      end
      instance_eval(code)
    end
  end

  # Returns nil if check: passes, else the message the form would show.
  def self.check(form, values)
    catch(:halt) do
      Checker.new.run(form["check"], values)
      nil
    end
  rescue StandardError => e
    e.message
  end

  # The widget of field `key`, or of `<key>_<n>`'s field; nil if no field.
  def self.widget(form, key)
    f = form["form"][key] || (key =~ /\A(.+)_\d+\z/ && form["form"][$1])
    f && f["widget"]
  end

  def self.script(form, values)
    empty = ->(v) { Array(v).join.empty? }
    # Split and joined as lib/form.rb and the pane do: trailing empty lines
    # go, and the last line has no newline.
    form["script"].split("\n").flat_map do |line|
      plain = line.scan(/\#\{([a-z_0-9]+)\}/).flatten
      next [] if plain.any? { |k| empty[values[k]] }
      # A checkbox or multi_select with nothing chosen empties its line,
      # #{:field} too, and one with no separator, its values an array,
      # writes the line once per value (ocForm.showLine).
      named = line.scan(/\#\{:?([a-z_0-9]+)\}/).flatten
      next [] if named.any? { |k| choice?(widget(form, k)) && empty[values[k]] }
      lines = [line]
      named.uniq.select { |k| values[k].is_a?(Array) }.each do |k|
        lines = lines.flat_map { |l| values[k].map { |v| l.gsub(/\#\{:?#{k}\}/) { v.to_s } } }
      end
      lines.map do |l|
        l.gsub(/\#\{zeropadding\((\w+), *(\d+)\)\}/) { values[$1].to_s.rjust($2.to_i, "0") }
         .gsub(/\#\{:?([a-z_0-9]+)\}/) { values[$1].to_s }
      end
    end.join("\n")
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"
  opts = { check: true }
  OptionParser.new do |o|
    o.on("--apps-dir DIR") { |d| opts[:apps_dir] = File.expand_path(d) }
    o.on("--no-check") { opts[:check] = false }
  end.parse!
  form_path, *pairs = ARGV
  abort "usage: form_helper.rb [--apps-dir DIR] [--no-check] FORM [field=value]..." unless form_path
  form = opts.key?(:apps_dir) ? FormHelper.render(form_path, opts[:apps_dir]) : FormHelper.render(form_path)
  values = FormHelper.defaults(form, pairs.to_h { |p| p.split("=", 2) })
  if opts[:check] && (msg = FormHelper.check(form, values))
    warn "check: rejected: " + msg
    exit 1
  end
  print FormHelper.script(form, values)
end
