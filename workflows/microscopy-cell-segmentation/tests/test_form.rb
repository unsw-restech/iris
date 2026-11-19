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
  SLUG = "microscopy-cell-segmentation"
  JOB_NAME = "iris_microscopy_cell_segmentation"
  # The first bytes of each kind of file: the check reads no further.
  TIFF = "II*\x00\x08\x00\x00\x00"
  BIG_TIFF = "MM\x00+\x00\x08\x00\x00"
  PNG = "\x89PNG\r\n\x1a\n"

  def setup
    skip "needs #{SCRATCH}" unless File.directory?(SCRATCH)
    @form = FormHelper.render(FORM)
    @tmp = Dir.mktmpdir("iris-form-test-", SCRATCH)
    @ds = File.join(@tmp, "dataset")
    FileUtils.mkdir_p([File.join(@ds, "images"), File.join(@ds, "train", "images"), File.join(@ds, "train", "labels")])
    %w[field01.tif field02.tif].each { |n| File.binwrite(File.join(@ds, "images", n), TIFF) }
    %w[pair01.tif pair02.tif].each do |n|
      File.binwrite(File.join(@ds, "train", "images", n), TIFF)
      File.binwrite(File.join(@ds, "train", "labels", n), TIFF)
    end
  end

  def teardown
    FileUtils.rm_rf(@tmp) if @tmp
  end

  def check(dataset = @ds, **given)
    FormHelper.check(@form, FormHelper.defaults(@form, given.merge(dataset: dataset)))
  end

  def script(**given)
    FormHelper.script(@form, FormHelper.defaults(@form, given.merge(dataset: @ds)))
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
  end

  def test_rejects_a_path_with_spaces
    spaced = File.join(@tmp, "my dataset")
    FileUtils.cp_r(@ds, spaced)
    assert_match(/spaces/, check(spaced))
  end

  def test_rejects_a_dataset_with_no_image_set_folder
    FileUtils.rm_rf(File.join(@ds, "images"))
    assert_match(/No image set/, check)
  end

  def test_rejects_an_empty_image_set
    FileUtils.rm(Dir.glob(File.join(@ds, "images", "*")))
    assert_match(/No image set/, check)
  end

  def test_a_folder_inside_images_is_not_an_image
    FileUtils.rm(Dir.glob(File.join(@ds, "images", "*")))
    FileUtils.mkdir_p(File.join(@ds, "images", "field01"))
    assert_match(/No image set/, check)
  end

  def test_a_big_tiff_in_either_byte_order_passes
    File.binwrite(File.join(@ds, "images", "field03.tif"), BIG_TIFF)
    assert_nil check
  end

  def test_rejects_an_image_that_is_not_a_tiff_and_names_it
    File.binwrite(File.join(@ds, "images", "field03.png"), PNG)
    msg = check
    assert_match(/not TIFFs/, msg)
    assert_includes msg, "field03.png"
  end

  def test_rejects_an_empty_image_file
    FileUtils.touch(File.join(@ds, "images", "field03.tif"))
    assert_includes check, "field03.tif"
  end

  def test_rejects_a_training_image_or_label_that_is_not_a_tiff_and_names_it
    %w[images labels].each do |folder|
      File.binwrite(File.join(@ds, "train", folder, "pair02.tif"), PNG)
      msg = check
      assert_match(/not TIFFs/, msg, folder)
      assert_includes msg, File.join("train", folder), folder
      assert_includes msg, "pair02.tif", folder
      File.binwrite(File.join(@ds, "train", folder, "pair02.tif"), TIFF)
    end
  end

  def test_rejects_missing_train_images_or_labels
    FileUtils.rm_rf(File.join(@ds, "train", "labels"))
    assert_match(%r{Missing train/images or train/labels}, check)
    FileUtils.mkdir_p(File.join(@ds, "train", "labels"))
    FileUtils.rm_rf(File.join(@ds, "train", "images"))
    assert_match(%r{Missing train/images or train/labels}, check)
  end

  def test_rejects_no_training_images
    FileUtils.rm(Dir.glob(File.join(@ds, "train", "*", "*")))
    assert_match(/No training images/, check)
  end

  def test_rejects_training_images_and_labels_whose_file_names_differ_and_names_them
    FileUtils.mv(File.join(@ds, "train", "labels", "pair02.tif"), File.join(@ds, "train", "labels", "pair03.tif"))
    msg = check
    assert_match(/different file names/, msg)
    assert_includes msg, "pair02.tif"
    assert_includes msg, "pair03.tif"
  end

  def test_the_usage_tag_and_the_environment_version_are_this_workflows
    assert_includes script, "#PBS -A iris-#{SLUG}\n"
    assert_includes script, "\nIRIS_ENV_VERSION=microct/1\n"
  end

  def test_experiment_and_job_name_default_to_the_slug
    assert_includes script, %(--experiment "#{SLUG}" \\\n)
    assert_includes script, "#PBS -N #{JOB_NAME}\n"
    assert_includes script, %(--field "job_name=#{JOB_NAME}" \\\n)
  end

  def test_the_job_output_goes_to_the_datasets_runs_folder
    assert_includes script, "#PBS -o #{@ds}/runs/\n"
  end

  def test_a_blank_seed_still_passes_seed_to_the_entry_point
    assert_includes script(seed: ""), %(--seed "" \\\n)
  end

  def test_the_pane_holds_this_workflows_entry_script_for_editing
    assert_includes script, "# Edit the workflow code below\n"
    assert_includes script, File.read(File.join(WORKFLOW, "src", "run.py"))
  end

  def test_rejects_a_blank_experiment_or_one_that_breaks_the_script
    ["", "  ", "say \"hi\"", "$HOME", "a`b`"].each do |name|
      assert_match(/experiment name/, check(experiment: name), name.inspect)
    end
  end

  def test_rejects_a_job_name_that_breaks_the_script
    ["", "my job", "a\"b", "$x"].each do |name|
      assert_match(/job name/, check(job_name: name), name.inspect)
    end
  end

  def test_rejects_a_walltime_of_zero
    assert_match(/Walltime/, check(time_1: 0, time_2: 0))
  end

  def test_mail_on_end_and_abnormal_end_by_default
    assert_includes script, "#PBS -m ae\n"
  end
end
