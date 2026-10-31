# What this form accepts, rejects and generates, beyond what every imaging
# form's script holds (lib/tests/imaging_form.rb). Needs Ruby and a
# /srv/scratch/$USER to build fixture datasets in, so bin/katana-test runs
# it on Katana.

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../../../lib/tests/form_helper"

class FormTest < Minitest::Test
  WORKFLOW = File.expand_path("..", __dir__)
  FORM = File.join(WORKFLOW, "form.yml.erb")
  SCRATCH = "/srv/scratch/" + ENV["USER"].to_s

  def setup
    skip "needs #{SCRATCH}" unless File.directory?(SCRATCH)
    @form = FormHelper.render(FORM)
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

  def test_the_job_output_goes_to_the_datasets_runs_folder
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds))
    assert_includes script, "#PBS -o #{@ds}/runs/\n"
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
    [FormHelper.render(FORM, SYSTEM_APPS_DIR), @form].each do |form|
      script = FormHelper.script(form, FormHelper.defaults(form, dataset: @ds))
      refute_includes script, "iris-view"
      refute_includes script, "iris-compare"
      assert script.end_with?("\niris_done\n"), script.lines.last(3).join
    end
  end

  def test_from_the_system_clone_experiment_help_names_the_module
    help = FormHelper.render(FORM, SYSTEM_APPS_DIR + "/")["form"]["experiment"]["help"]
    assert_includes help, "module load iris"
    assert_includes help, " iris-compare "
    refute_includes help, "/bin/iris-"
  end

  def test_from_another_clone_experiment_help_names_the_clones_iris_compare
    help = @form["form"]["experiment"]["help"]
    assert_includes help, " #{CLONE}/bin/iris-compare "
    refute_includes help, "module load iris"
  end

  def test_both_clones_set_code_to_their_own_folder_and_never_load_the_module
    { SYSTEM_APPS_DIR => "#{SYSTEM_APPS_DIR}/microct-2d-segmentation", File.dirname(WORKFLOW) => WORKFLOW }.each do |apps_dir, code|
      form = FormHelper.render(FORM, apps_dir)
      script = FormHelper.script(form, FormHelper.defaults(form, dataset: @ds))
      assert_includes script, %(\nCODE="#{code}"\n)
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
