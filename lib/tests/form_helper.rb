# Render a form.yml.erb the way OpenComposer 1.9.0 does, for tests and for
# submitting a job without the browser. Every workflow's form tests use it.
#
#   render     ERB with @apps_dir and @OC_DIR_NAME set (the GET), then YAML;
#              @apps_dir is the folder holding the form's workflow folder
#              unless given (nil, as on OpenComposer's re-read at submit)
#   check      eval the check: section with each field as @field, and
#              oc_assert raising as OpenComposer's does (run.rb rescues it
#              and re-renders the form with the values kept)
#   script     fill #{field}, #{:field} and #{zeropadding(f, n)}, dropping a
#              line whose plain #{field} is empty, as the page's script pane
#              does (lib/form.rb output_script_js)
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

  # The values a researcher submits without touching anything but `given`.
  def self.defaults(form, given = {})
    values = {}
    form["form"].each do |key, f|
      v = f["value"]
      case f["widget"]
      when "checkbox"
        chosen = Array(v).map { |label| f["options"].find { |o| o[0] == label }[1] }
        values[key] = chosen.join(f["separator"] || ",")
      when "number"
        if v.is_a?(Array) then v.each_with_index { |x, i| values["#{key}_#{i + 1}"] = x }
        else values[key] = v end
      else
        values[key] = v
      end
    end
    values.merge(given.transform_keys(&:to_s))
  end

  class Checker
    def oc_assert(cond, msg) = (raise RuntimeError, msg unless cond)

    def run(code, values)
      values.each { |k, v| instance_variable_set("@#{k}", v) }
      instance_eval(code)
    end
  end

  # Returns nil if check: passes, else the message the form would show.
  def self.check(form, values)
    Checker.new.run(form["check"], values)
    nil
  rescue RuntimeError => e
    e.message
  end

  def self.script(form, values)
    form["script"].lines.filter_map do |line|
      plain = line.scan(/\#\{([a-z_0-9]+)\}/).flatten
      next if plain.any? { |k| values[k].to_s.empty? }
      line.gsub(/\#\{zeropadding\((\w+), *(\d+)\)\}/) { values[$1].to_s.rjust($2.to_i, "0") }
          .gsub(/\#\{:?([a-z_0-9]+)\}/) { values[$1].to_s }
    end.join
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
