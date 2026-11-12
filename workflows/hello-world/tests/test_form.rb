# What hello-world's form accepts, rejects and generates. Its module list
# comes from Katana's Environment Modules at render time, so bin/katana-test
# runs it on Katana.

require "minitest/autorun"
require_relative "../../../lib/tests/form_helper"

class FormTest < Minitest::Test
  WORKFLOW = File.expand_path("..", __dir__)
  FORM = File.join(WORKFLOW, "form.yml.erb")
  # The modulecmd the form runs to list modules, read from the form so the
  # two can't differ.
  MODULECMD = File.read(FORM)[%r{"(/[^"]+/modulecmd\.tcl)"}, 1]

  def setup
    skip "needs #{MODULECMD}" unless File.exist?(MODULECMD)
    @form = FormHelper.render(FORM)
  end

  def values(**given) = FormHelper.defaults(@form, given)

  def test_the_defaults_pass
    assert_nil FormHelper.check(@form, values)
  end

  # hello-world fails check: with halt, a bare error page holding the message.
  def test_rejects_a_blank_output_directory
    assert_equal "Choose an output directory.", FormHelper.check(@form, values(working_dir: " "))
  end

  def test_rejects_a_zero_or_too_long_walltime
    assert_equal "Walltime cannot be zero.", FormHelper.check(@form, values(time_1: 0, time_2: 0))
    assert_equal "Maximum walltime on Katana is 200 hours.", FormHelper.check(@form, values(time_1: 201))
  end

  def test_the_default_script_requests_the_defaults_and_runs_its_own_clone
    script = FormHelper.script(@form, values)
    assert_includes script, "#PBS -N iris_hello_world\n"
    assert_includes script, "#PBS -A iris-hello-world\n"
    assert_includes script, "#PBS -l select=1:ncpus=1:mem=4gb:ngpus=0\n"
    assert_includes script, "#PBS -l walltime=1:00:00\n"
    assert_includes script, %(\nCODE="#{WORKFLOW}"\n)
  end

  # Unchecked and unchosen, mail events, -j and modules leave no line.
  def test_options_left_unset_leave_no_line
    script = FormHelper.script(@form, values)
    refute_match(/^#PBS -m/, script)
    refute_match(/^#PBS -j/, script)
    refute_match(/^module load/, script)
  end

  def test_the_modules_listed_are_katanas_and_load_on_one_line
    names = @form["form"]["module"]["options"].map(&:first)
    refute_empty names, "no modules listed from #{MODULECMD}"
    script = FormHelper.script(@form, values(module: names.first(2).join(" ")))
    assert_includes script, "\nmodule load #{names.first(2).join(" ")}\n"
  end
end
