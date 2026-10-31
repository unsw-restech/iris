# What every imaging form's script holds, checked on the script the form
# renders rather than its ERB source, so what is checked is what
# OpenComposer submits. An imaging form carries its entry script in its
# script (GLOSSARY.md); bin/check finds them and runs this on each:
#
#   ruby lib/tests/imaging_form.rb FORM...
#
# which prints "<form>: <problem>" for each problem and exits 1 if any.
# The parts, in order:
#   - #!/bin/bash, then the PBS header with the usage tag, #PBS -A iris-<slug>
#   - CODE, the form's own folder; COMMIT, its clone's commit at render
#     time; the guard that stops the job when CODE is empty, as it is when
#     OpenComposer re-reads the form without @apps_dir; ENV_DIR
#   - sourcing the job library
#   - the banner
#   - the quoted heredoc writing run.py, holding the entry script byte for
#     byte up to its end marker (ADR-0006)
#   - on the next line, the call that records the run's code, naming the
#     entry script, so a run.py Python cannot start still leaves its diff
#   - the python call on the run directory's run.py
# No other line holds a heredoc: script: builds files with printf. The
# entry script holds neither #{ (OpenComposer would substitute a field,
# or drop the line when the field is empty) nor <% (ERB).
#
# These constants are the only test-side copy of the lines a script must
# hold: renaming one changes the form, the job library and this file.

require_relative "form_helper"

module ImagingForm
  SOURCE = %(source "$CODE/../../lib/iris-job.sh")
  CODE_GUARD = %([ -n "$CODE" ] || { echo "ERROR: the form could not locate its IRIS clone."; exit 1; })
  BANNER = "# Workflow code: edit below. Set the form fields first; changing a field afterwards discards these edits."
  END_MARKER = "IRIS_RUN_PY_END"
  OPENER = %(cat > "$RUN_DIR/run.py" <<'#{END_MARKER}')
  RECORD = "iris_record_code"
  PYTHON = %(python "$RUN_DIR/run.py")

  # The problems with the imaging form at `form_path`, as
  # "<form_path>: <problem>" lines; empty if it has none.
  def self.problems(form_path)
    Check.new(form_path).problems.map { |p| "#{form_path}: #{p}" }
  end

  class Check
    def initialize(form_path)
      @path = form_path
      @code = File.dirname(File.expand_path(form_path))
      @slug = File.basename(@code)
      @problems = []
    end

    def problems
      script = render(@path)
      return @problems unless script
      @lines = script.lines
      @entry = (@lines.find { |l| l.start_with?("#{RECORD} ") } || "#{RECORD} src/run.py").split(" ", 2)[1].strip
      entry_text
      ordered_parts
      other_heredocs
      unrendered = render(@path, nil)
      @problems << %(rendered without @apps_dir, CODE is not "", so the guard cannot stop the job) if unrendered && !unrendered.lines.include?(%(CODE=""\n))
      @problems
    end

    private

    # The script the form renders with its defaults, every field without
    # one filled in; nil, with a problem, if it does not render.
    def render(path, *apps_dir)
      form = FormHelper.render(path, *apps_dir)
      values = FormHelper.defaults(form).transform_values { |v| v.nil? ? "x" : v }
      FormHelper.script(form, values)
    rescue StandardError, SyntaxError => e
      @problems << "does not render#{apps_dir.empty? ? "" : " without @apps_dir"}: #{e.message.lines.first.strip}"
      nil
    end

    def entry_text
      file = File.join(@code, @entry)
      unless File.file?(file)
        @problems << "no entry script at #{file}"
        return
      end
      @entry_text = File.binread(file)
      @entry_text.lines.each_with_index do |l, i|
        ["\#{", "<%"].select { |t| l.include?(t) }.each { |t| @problems << "#{file}:#{i + 1}: #{t} in the entry script" }
      end
    end

    def commit
      IO.popen(["git", "-C", @code, "rev-parse", "HEAD"], err: File::NULL, &:read).strip
    rescue StandardError
      ""
    end

    # [description, finder]: each finder takes a line index and returns
    # the index just past the part if it starts at that line, else nil.
    def parts
      line = ->(want) { ->(i) { @lines[i] == want + "\n" ? i + 1 : nil } }
      [
        ["the PBS header with #PBS -A iris-#{@slug}", lambda { |i|
          return nil unless i.zero? && @lines[0] == "#!/bin/bash\n"
          j = 1
          j += 1 while @lines[j]&.start_with?("#PBS ")
          @lines[1...j].include?("#PBS -A iris-#{@slug}\n") ? j : nil
        }],
        [%(CODE="#{@code}"), line.(%(CODE="#{@code}"))],
        [%(COMMIT="#{commit}", the clone's commit at render time), line.(%(COMMIT="#{commit}"))],
        ["the CODE guard: #{CODE_GUARD}", line.(CODE_GUARD)],
        ["ENV_DIR=<environment>", ->(i) { @lines[i].match?(/\AENV_DIR=\S+\n\z/) ? i + 1 : nil }],
        [SOURCE, line.(SOURCE)],
        ["the banner: #{BANNER}", line.(BANNER)],
        ["#{OPENER}, holding #{@entry} byte for byte, then #{END_MARKER}", lambda { |i|
          return nil unless @lines[i] == OPENER + "\n"
          body = @entry_text.to_s + END_MARKER + "\n"
          @lines[(i + 1)..].join.start_with?(body) ? i + 1 + body.lines.size : nil
        }],
        ["#{RECORD} #{@entry}, on the line after the heredoc", line.("#{RECORD} #{@entry}")],
        [PYTHON, ->(i) { @lines[i].match?(/\A#{Regexp.escape(PYTHON)}( |\n)/) ? i + 1 : nil }],
      ]
    end

    # Any heredoc in the script but the entry script's: script: builds
    # other files with printf '%s\n'.
    def other_heredocs
      opener = @lines.index(OPENER + "\n")
      last = opener && (@lines[(opener + 1)..].index(END_MARKER + "\n") || @lines.size) + opener + 1
      @lines.each_with_index do |l, i|
        next if opener && (opener..last).cover?(i)
        @problems << "line #{i + 1}: a heredoc besides the entry script's (build files with printf '%s\\n'): #{l.strip}" if l.include?("<<")
      end
    end

    def ordered_parts
      openers = @lines.count(OPENER + "\n")
      @problems << "#{openers} lines #{OPENER}; the entry script's heredoc opens once" if openers > 1
      at = 0
      after_heredoc = false
      parts.each do |desc, found|
        # The record call must follow the heredoc directly.
        hit = if desc.start_with?(RECORD) && after_heredoc then found.(at)
              else (at...@lines.size).lazy.filter_map { |i| found.(i) }.first
              end
        after_heredoc = false
        if hit
          after_heredoc = desc.start_with?(OPENER)
          at = hit
        elsif (0...@lines.size).any? { |i| found.(i) }
          @problems << "#{desc}: out of order (see lib/tests/imaging_form.rb)"
        else
          @problems << "no #{desc} (see lib/tests/imaging_form.rb)"
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  problems = ARGV.flat_map { |f| ImagingForm.problems(f) }
  puts problems
  exit(problems.empty? ? 0 : 1)
end
