# What every imaging form's rendered script must hold, checked by
# imaging_form.rb, against throwaway clones holding the reference form
# with one part broken. Needs only Ruby and git, so bin/check runs it:
#
#   ruby lib/tests/test_imaging_form.rb

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "form_helper"
require_relative "imaging_form"

class ImagingFormTest < Minitest::Test
  REFERENCE = File.expand_path("../../workflows/microct-2d-segmentation", __dir__)

  # A clone in a temporary folder with one commit, holding the reference
  # workflow's form and entry script as workflows/seg, its usage tag
  # renamed; the block, if given, edits the form's text first.
  def setup
    @clone = Dir.mktmpdir("iris-imaging-form-test-")
    @code = File.join(@clone, "workflows", "seg")
    @form = File.join(@code, "form.yml.erb")
    FileUtils.mkdir_p(File.join(@code, "src"))
    FileUtils.cp(File.join(REFERENCE, "src", "run.py"), File.join(@code, "src"))
    File.write(@form, File.read(File.join(REFERENCE, "form.yml.erb")).sub("#PBS -A iris-microct-2d-segmentation", "#PBS -A iris-seg"))
    git("init", "-q")
    commit
  end

  def teardown
    FileUtils.rm_rf(@clone)
  end

  def git(*args)
    out = IO.popen(["git", "-C", @clone, *args], &:read)
    raise "git #{args.join(" ")} failed" unless $?.success?
    out
  end

  def commit
    git("add", "-A")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "c", "--allow-empty")
    git("rev-parse", "HEAD").strip
  end

  def test_the_helper_renders_a_form_given_its_path_from_its_own_clone
    form = FormHelper.render(@form)
    script = FormHelper.script(form, FormHelper.defaults(form, dataset: "/srv/scratch/z1234567/ds"))
    assert_includes script, %(\nCODE="#{@code}"\n)
    assert_includes script, "#PBS -A iris-seg\n"
  end

  # Edits the form's ERB source with the block, then commits it.
  def edit_form
    File.write(@form, yield(File.read(@form)))
    commit
  end

  # The form's source without the lines holding `text`.
  def drop(text)
    edit_form { |s| s.lines.reject { |l| l.include?(text) }.join }
  end

  def assert_fails(pattern)
    problems = ImagingForm.problems(@form)
    refute_empty problems, "expected a failure matching #{pattern.inspect}"
    assert problems.any? { |p| p.start_with?("#{@form}: ") && p.match?(pattern) }, problems.join("\n")
  end

  def test_the_reference_form_passes
    assert_equal [], ImagingForm.problems(@form)
  end

  def test_a_form_that_does_not_record_the_runs_code_fails
    drop("  " + ImagingForm::RECORD)
    assert_fails(/no #{ImagingForm::RECORD}/)
  end

  def test_a_form_without_its_usage_tag_fails
    drop("#PBS -A iris-seg")
    assert_fails(/no the PBS header with #PBS -A iris-seg/)
  end

  def test_a_form_tagged_for_another_workflow_fails
    edit_form { |s| s.sub("#PBS -A iris-seg", "#PBS -A iris-microct-2d-segmentation") }
    assert_fails(/#PBS -A iris-seg/)
  end

  def test_a_form_without_the_code_guard_fails
    drop(ImagingForm::CODE_GUARD)
    assert_fails(/no the CODE guard/)
  end

  def test_a_form_whose_code_ignores_a_missing_apps_dir_fails
    edit_form { |s| s.sub('<% code = @apps_dir ? File.expand_path(File.join(@apps_dir, @OC_DIR_NAME)) : "" %>', '<% code = File.expand_path(File.join(@apps_dir.to_s, @OC_DIR_NAME)) %>') }
    assert_fails(/without @apps_dir/)
  end

  def test_a_form_without_env_dir_fails
    drop("  ENV_DIR=")
    assert_fails(/no ENV_DIR/)
  end

  def test_a_form_that_does_not_source_the_job_library_fails
    drop("  " + ImagingForm::SOURCE)
    assert_fails(/no #{Regexp.escape(ImagingForm::SOURCE)}/)
  end

  def test_a_form_without_the_banner_fails
    drop(ImagingForm::BANNER)
    assert_fails(/no the banner/)
  end

  def test_a_form_whose_heredoc_never_ends_fails
    edit_form { |s| s.lines.reject { |l| l == "  #{ImagingForm::END_MARKER}\n" }.join }
    assert_fails(/no #{Regexp.escape(ImagingForm::OPENER)}, holding src\/run.py byte for byte/)
  end

  def test_a_form_whose_heredoc_holds_other_code_fails
    edit_form { |s| s.sub("<%= entry_code -%>", "  print('not the entry script')\n") }
    assert_fails(/byte for byte/)
  end

  def test_a_form_that_does_not_run_run_py_fails
    edit_form { |s| s.sub("  #{ImagingForm::PYTHON} ", '  python "$CODE/src/run.py" ') }
    assert_fails(/no #{Regexp.escape(ImagingForm::PYTHON)}/)
  end

  def test_a_form_that_records_its_code_after_python_runs_fails
    record = File.read(@form).lines.find { |l| l.start_with?("  " + ImagingForm::RECORD) }
    edit_form { |s| s.sub(record, "").sub("  iris_done\n", "#{record}  iris_done\n") }
    assert_fails(/#{ImagingForm::RECORD} src\/run.py, on the line after the heredoc: out of order/)
  end

  def test_a_form_that_sources_the_job_library_after_the_banner_fails
    source = "  #{ImagingForm::SOURCE}\n"
    edit_form { |s| s.sub(source, "").sub("  cat > ", "#{source}  cat > ") }
    assert_fails(/out of order/)
  end

  def test_an_entry_script_with_an_opencomposer_substitution_fails
    File.write(File.join(@code, "src", "run.py"), "print(\"\#{epochs}\")\n", mode: "a")
    commit
    assert_fails(%r{src/run.py:\d+: \#\{ in the entry script})
  end

  def test_an_entry_script_with_an_erb_tag_fails
    File.write(File.join(@code, "src", "run.py"), "# <%= 1 %>\n", mode: "a")
    commit
    assert_fails(%r{src/run.py:\d+: <% in the entry script})
  end

  def test_a_form_with_another_heredoc_fails
    edit_form { |s| s.sub("  iris_done\n", "  cat > x <<EOF\n  EOF\n  iris_done\n") }
    assert_fails(/line \d+: a heredoc besides the entry script's/)
  end

  def test_an_entry_script_holding_a_heredoc_like_line_passes
    File.write(File.join(@code, "src", "run.py"), "x = 1 << 2  # cat <<EOF\n", mode: "a")
    commit
    assert_equal [], ImagingForm.problems(@form)
  end

  def test_a_form_whose_commit_is_not_the_clones_at_render_time_fails
    edit_form { |s| s.sub('COMMIT="<%= commit %>"', 'COMMIT=""') }
    assert_fails(/no COMMIT="\h{40}"/)
  end
end
