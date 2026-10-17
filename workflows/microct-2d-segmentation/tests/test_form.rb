# What the form accepts, rejects and generates. Needs Ruby and a
# /srv/scratch/$USER to build fixture datasets in, so it runs on Katana:
#
#   module load ruby/3.2.0 && ruby workflows/microct-2d-segmentation/tests/test_form.rb

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
    assert_includes script, %(--seed ""\n)
  end

  def test_mail_on_end_and_abnormal_end_by_default
    script = FormHelper.script(@form, FormHelper.defaults(@form, dataset: @ds))
    assert_includes script, "#PBS -m ae\n"
  end
end
