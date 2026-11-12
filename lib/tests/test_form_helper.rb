# The form test helper renders, checks and fills a form as the pinned fork
# commit does (form_helper.rb's header names it), on small forms written
# to a temporary folder. Needs only Ruby, so bin/check runs it:
#
#   ruby lib/tests/test_form_helper.rb

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "form_helper"

class FormHelperTest < Minitest::Test
  def setup
    @apps = Dir.mktmpdir("iris-form-helper-test-")
  end

  def teardown
    FileUtils.rm_rf(@apps)
  end

  # Writes `text` as workflows/<name>/form.yml.erb and renders it.
  def form(text, name = "fixture")
    path = File.join(@apps, name, "form.yml.erb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    FormHelper.render(path)
  end

  def script(f, given = {})
    FormHelper.script(f, FormHelper.defaults(f, given))
  end

  def test_halt_in_check_rejects_with_its_message
    f = form(<<~YAML)
      form:
        hours:
          widget: number
          value: 0
      script: "echo"
      check: |
        halt 500, "Walltime cannot be zero." if @hours.to_i == 0
    YAML
    assert_equal "Walltime cannot be zero.", FormHelper.check(f, FormHelper.defaults(f))
    assert_nil FormHelper.check(f, FormHelper.defaults(f, hours: 2))
  end

  # run.rb rescues every exception from check: and shows its message.
  def test_any_error_in_check_rejects_with_its_message
    f = form(<<~YAML)
      form:
        mem:
          widget: text
          value: "lots"
      script: "echo"
      check: |
        Integer(@mem)
    YAML
    assert_match(/invalid value for Integer\(\): "lots"/, FormHelper.check(f, FormHelper.defaults(f)))
  end

  MAIL = <<~YAML
    form:
      mail_events:
        widget: checkbox
        separator: ""
        options:
          - [ "On abort", "a" ]
          - [ "On end",   "e" ]
    script: |
      #PBS -m \#{mail_events}
      --field "mail_events=\#{:mail_events}"
      done
  YAML

  def test_a_checked_checkbox_fills_both_forms_of_its_field
    assert_equal %(#PBS -m ae\n--field "mail_events=ae"\ndone\n), script(form(MAIL), mail_events: "ae")
  end

  # ocForm.showLine empties a checkbox's line when nothing is checked,
  # however the line names it.
  def test_an_unchecked_checkbox_drops_every_line_holding_it
    assert_equal "done\n", script(form(MAIL))
  end

  # With no separator, ocForm.showLine writes the line once per value.
  def test_a_checkbox_with_no_separator_repeats_its_line_per_checked_option
    f = form(<<~YAML)
      form:
        steps:
          widget: checkbox
          value: [ "Train", "Segment" ]
          options:
            - [ "Train",   "train"   ]
            - [ "Score",   "score"   ]
            - [ "Segment", "segment" ]
      script: |
        run \#{steps}
    YAML
    assert_equal "run train\nrun segment\n", script(f)
  end

  # run.rb's set_check_value: one checked value is itself, several an array.
  def test_check_sees_a_checkbox_with_no_separator_as_run_rb_sets_it
    f = form(<<~YAML)
      form:
        steps:
          widget: checkbox
          options:
            - [ "Train", "train" ]
            - [ "Score", "score" ]
      script: "echo"
      check: |
        oc_assert(false, @steps.inspect)
    YAML
    assert_equal "nil", FormHelper.check(f, FormHelper.defaults(f))
    assert_equal '"train"', FormHelper.check(f, FormHelper.defaults(f, steps: ["train"]))
    assert_equal '["train", "score"]', FormHelper.check(f, FormHelper.defaults(f, steps: %w[train score]))
  end

  MODULES = <<~YAML
    form:
      module:
        widget: multi_select
        separator: " "
        value: [ "GCC 14", "julia/1.11" ]
        options:
          - [ "GCC 14", "gcc/14.2.0" ]
          - [ "R 4.4",  "R/4.4.1"    ]
    script: |
      module load \#{module}
    check: |
      oc_assert(false, @module)
  YAML

  # The fork, unlike 1.9.0, keeps an entry that is no option as typed:
  # form.js's getValue falls back to its text, run.rb's check to its value.
  def test_a_multi_select_fills_its_options_values_and_typed_entries
    f = form(MODULES)
    assert_equal "module load gcc/14.2.0 julia/1.11\n", script(f)
    assert_equal "gcc/14.2.0 julia/1.11", FormHelper.check(f, FormHelper.defaults(f))
  end
end
