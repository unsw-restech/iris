# What the form accepts, rejects and generates. Needs Ruby and a
# /srv/scratch/$USER to build fixture datasets in, so bin/katana-test runs
# it on Katana.

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "form_helper"

class FormTest < Minitest::Test
  SCRATCH = "/srv/scratch/" + ENV["USER"].to_s

  def setup
    skip "needs #{SCRATCH}" unless File.directory?(SCRATCH)
    @form = FormHelper.render
    @tmp = Dir.mktmpdir("iris-form-test-", SCRATCH)
    @ds = File.join(@tmp, "dataset")
    FileUtils.mkdir_p([File.join(@ds, "volume"), File.join(@ds, "train", "images"), File.join(@ds, "train", "labels")])
    FileUtils.touch(File.join(@ds, "volume", "block00000000.nc"))
    %w[slice0010.tif slice0200.tif].each do |n|
      FileUtils.touch(File.join(@ds, "train", "images", n))
      FileUtils.touch(File.join(@ds, "train", "labels", n))
    end
  end

  def teardown
    FileUtils.rm_rf(@tmp) if @tmp
  end

  def check(dataset = @ds, **given)
    FormHelper.check(@form, FormHelper.defaults(@form, given.merge(dataset: dataset)))
  end

  def test_a_laid_out_dataset_passes
    assert_nil check
  end

  def test_a_runs_folder_from_earlier_runs_is_allowed
    FileUtils.mkdir_p(File.join(@ds, "runs", "9544829"))
    assert_nil check
  end

  def test_rejects_a_folder_outside_scratch
    Dir.mktmpdir do |outside|
      FileUtils.cp_r(Dir.glob(File.join(@ds, "*")), outside)
      assert_match(/inside your scratch/, check(outside))
    end
    assert_match(/inside your scratch/, check(SCRATCH + "-other/dataset"))
  end

  def test_rejects_a_volume_with_no_nc_file
    FileUtils.rm(File.join(@ds, "volume", "block00000000.nc"))
    FileUtils.touch(File.join(@ds, "volume", "block00000000.tif"))
    assert_match(/No \.nc files/, check)
  end

  def test_rejects_missing_train_images_or_labels
    FileUtils.rm_rf(File.join(@ds, "train", "labels"))
    assert_match(%r{Missing train/images or train/labels}, check)
    FileUtils.mkdir_p(File.join(@ds, "train", "labels"))
    FileUtils.rm_rf(File.join(@ds, "train", "images"))
    assert_match(%r{Missing train/images or train/labels}, check)
  end

  def test_rejects_mismatched_filenames_and_names_them
    FileUtils.mv(File.join(@ds, "train", "labels", "slice0200.tif"), File.join(@ds, "train", "labels", "slice0201.tif"))
    msg = check
    assert_match(/different file names/, msg)
    assert_includes msg, "slice0200.tif"
    assert_includes msg, "slice0201.tif"
  end

  def test_rejects_a_path_with_spaces
    spaced = File.join(@tmp, "my dataset")
    FileUtils.cp_r(@ds, spaced)
    assert_match(/spaces/, check(spaced))
  end

  def test_script_tags_usage_and_sources_the_job_library
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds))
    assert_includes script, "#PBS -A iris-microct-2d-segmentation\n"
    assert_includes script, "#PBS -o #{@ds}/runs/\n"
    assert_includes script, %(CODE="#{FormHelper::WORKFLOW}"\n)
    assert_includes script, %(source "$CODE/../../lib/iris-job.sh"\n)
  end

  def test_a_blank_seed_still_passes_seed_to_the_entry_point
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds, seed: ""))
    assert_includes script, %(--seed "" \\\n)
  end

  def test_experiment_defaults_to_the_slug
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds))
    assert_includes script, %(--experiment "microct-2d-segmentation" \\\n)
  end

  SYSTEM_APPS_DIR = "/srv/scratch/katana_ai/iris/code/workflows"
  CLONE = File.expand_path("../../..", __dir__)

  # The job library prints the iris-view and iris-compare lines, per clone
  # (test_job_lib.py); the script only asks for them once training is done.
  def test_the_job_library_prints_the_view_lines_after_training
    [FormHelper.render(SYSTEM_APPS_DIR), @form].each do |form|
      script = FormHelper.script(form, FormHelper.defaults(form, dataset: @ds))
      refute_includes script, "iris-view"
      refute_includes script, "iris-compare"
      assert_match(/\npython "\$RUN_DIR\/run.py" \\\n.*\niris_done\n\z/m, script.split("\nIRIS_RUN_PY_END\n", 2)[1])
    end
  end

  def test_from_the_system_clone_experiment_help_names_the_module
    help = FormHelper.render(SYSTEM_APPS_DIR + "/")["form"]["experiment"]["help"]
    assert_includes help, "module load iris"
    assert_includes help, " iris-compare "
    refute_includes help, "/bin/iris-"
  end

  def test_from_another_clone_experiment_help_names_the_clones_iris_compare
    help = @form["form"]["experiment"]["help"]
    assert_includes help, " #{CLONE}/bin/iris-compare "
    refute_includes help, "module load iris"
  end

  def test_both_clones_embed_their_own_entry_script_and_never_load_the_module
    { SYSTEM_APPS_DIR => "#{SYSTEM_APPS_DIR}/microct-2d-segmentation", File.dirname(FormHelper::WORKFLOW) => FormHelper::WORKFLOW }.each do |apps_dir, code|
      form = FormHelper.render(apps_dir)
      script = FormHelper.script(form, FormHelper.defaults(form, dataset: @ds))
      assert_includes script, %(\nCODE="#{code}"\n)
      assert_includes script, %(\nsource "$CODE/../../lib/iris-job.sh"\n)
      assert_includes script, %(<<'IRIS_RUN_PY_END'\n#{File.read(File.join(code, "src", "run.py"))}IRIS_RUN_PY_END\n)
      assert_includes script, %(\npython "$RUN_DIR/run.py" \\\n)
      refute_match(/^\s*module load iris/, script)
    end
  end

  def test_a_named_experiment_reaches_the_entry_point
    assert_nil check(experiment: "pore sizes v2")
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds, experiment: "pore sizes v2"))
    assert_includes script, %(--experiment "pore sizes v2" \\\n)
  end

  def test_rejects_a_blank_experiment_or_one_that_breaks_the_script
    ["", "  ", "say \"hi\"", "$HOME", "a`b`", "a\\b", " leading"].each do |name|
      assert_match(/experiment name/, check(experiment: name), name.inspect)
    end
  end

  def test_rejects_a_job_name_that_breaks_the_script
    ["", "my job", "a\"b", "$x"].each do |name|
      assert_match(/job name/, check(job_name: name), name.inspect)
    end
  end

  def test_the_resource_fields_are_recorded
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds))
    assert_includes script, "--field ngpus=1 --field ncpus=8 --field mem=16gb \\\n"
    assert_includes script, "--field walltime=2:00:00 \\\n"
    assert_includes script, %(--field "job_name=iris_microct" --field "mail_events=ae"\n)
  end

  def test_mail_on_end_and_abnormal_end_by_default
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds))
    assert_includes script, "#PBS -m ae\n"
  end
end

# The script pane carries the entry script, which the job writes into the
# run directory and runs (ADR-0006). Rendered from a throwaway clone with
# one commit, so the render-time commit is known; needs only Ruby and git.
class EntryScriptTest < Minitest::Test
  BANNER = "# Workflow code: edit below. Set the form fields first; changing a field afterwards discards these edits.\n"

  def setup
    @clone = Dir.mktmpdir("iris-entry-test-")
    @code = File.join(@clone, "workflows", "microct-2d-segmentation")
    FileUtils.mkdir_p(File.join(@code, "src"))
    FileUtils.cp(File.join(FormHelper::WORKFLOW, "src", "run.py"), File.join(@code, "src"))
    git("init", "-q")
    git("add", ".")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "one")
    @head = git("rev-parse", "HEAD").strip
    form = FormHelper.render(File.join(@clone, "workflows"))
    @script = FormHelper.script(form, FormHelper.defaults(form, dataset: "/srv/scratch/z1234567/ds"))
  end

  def teardown
    FileUtils.rm_rf(@clone)
  end

  def git(*args)
    out = IO.popen(["git", "-C", @clone, *args], &:read)
    raise "git #{args.join(" ")} failed" unless $?.success?
    out
  end

  def test_the_script_holds_the_entry_script_byte_for_byte_after_the_banner
    entry = File.binread(File.join(@code, "src", "run.py"))
    opener = %(cat > "$RUN_DIR/run.py" <<'IRIS_RUN_PY_END'\n)
    assert_includes @script, "\n#{BANNER}"
    after_banner = @script.split("\n#{BANNER}", 2)[1]
    assert_includes after_banner, "\n#{opener}#{entry}IRIS_RUN_PY_END\n"
    assert_equal 1, @script.scan(opener).size
  end

  def test_the_script_carries_the_render_time_commit_for_commit_txt
    setup_part = @script.split(%(\nsource "$CODE/../../lib/iris-job.sh"\n), 2)[0]
    assert_includes setup_part, %(\nCOMMIT="#{@head}"\n)
  end

  def test_the_script_writes_run_py_before_the_python_call_and_runs_that_file
    write = @script.index(%(\ncat > "$RUN_DIR/run.py" <<'IRIS_RUN_PY_END'\n))
    call = @script.index(%(\npython "$RUN_DIR/run.py" \\\n))
    refute_nil write
    refute_nil call
    assert_operator write, :<, call
    assert_operator @script.index("\nIRIS_RUN_PY_END\n"), :<, call
    refute_includes @script, "src/run.py"
  end

  def test_the_pane_holds_header_setup_banner_code_and_call_in_order
    marks = ["#PBS -A iris-microct-2d-segmentation\n", %(\nsource "$CODE/../../lib/iris-job.sh"\n),
             "\n#{BANNER}", "<<'IRIS_RUN_PY_END'\n", %(\npython "$RUN_DIR/run.py" \\\n)]
    positions = marks.map { |m| @script.index(m) }
    refute_includes positions, nil
    assert_equal positions.sort, positions
  end
end
