# The rules form_fields.rb holds every form's fields to, on small forms
# written to a temporary folder. Needs only Ruby, so bin/check runs it:
#
#   ruby lib/tests/test_form_fields.rb

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "form_fields"

class FormFieldsTest < Minitest::Test
  def setup
    @apps = Dir.mktmpdir("iris-form-fields-test-")
  end

  def teardown
    FileUtils.rm_rf(@apps)
  end

  # `text` with `from` replaced by `to`, failing if `from` isn't in it, so a
  # fixture edit can't silently stop a case from breaking what it names.
  def swap(text, from, to)
    assert_includes text, from
    text.sub(from, to)
  end

  # The problems form_fields.rb finds in `text`, written as a form.
  def problems(text)
    path = File.join(@apps, "fixture", "form.yml.erb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    FormFields.problems(path).map { |p| p.delete_prefix(path + ": ") }
  end

  MAIL = <<~YAML
    form:
      mail_events:
        widget: select
        value: "On abort or end"
        options:
          - [ "On abort",        "a"  ]
          - [ "On abort or end", "ae" ]
      steps:
        widget: checkbox
        value: [ "Train" ]
        options:
          - [ "Train", "train" ]
          - [ "Score", "score" ]
    script: |
      #PBS -m \#{mail_events}
      --steps "\#{:steps}"
  YAML

  def test_values_that_label_their_options_pass
    assert_empty problems(swap(MAIL, ":steps", "steps"))
  end

  # lib/form.rb selects the option whose label is the value, so a data
  # value or a typo selects none and the browser shows the first.
  def test_a_select_value_that_labels_no_option_fails
    assert_equal [%(mail_events: value "ae" is no option's label)],
                 problems(swap(swap(MAIL, 'value: "On abort or end"', 'value: "ae"'), ":steps", "steps"))
  end

  def test_a_checkbox_value_that_labels_no_option_fails
    assert_equal [%(steps: value "train" is no option's label)],
                 problems(swap(swap(MAIL, 'value: [ "Train" ]', 'value: [ "train" ]'), ":steps", "steps"))
  end

  # ocForm.showLine drops a line naming a checkbox or multi_select with
  # nothing chosen, colon or not, so #{:field} promises a line it can't
  # keep (#184).
  def test_a_colon_on_a_checkbox_or_multi_select_fails
    assert_equal [%(script: \#{:steps} names a checkbox, whose line drops when nothing is chosen, colon or not (#184))],
                 problems(MAIL)
    multi = swap(MAIL, "widget: checkbox", "widget: multi_select")
    assert_equal [%(script: \#{:steps} names a multi_select, whose line drops when nothing is chosen, colon or not (#184))],
                 problems(multi)
  end

  def test_a_radio_value_that_labels_no_option_fails
    radio = swap(swap(MAIL, "widget: select", "widget: radio"), 'value: "On abort or end"', 'value: "ae"')
    assert_equal [%(mail_events: value "ae" is no option's label)], problems(swap(radio, ":steps", "steps"))
  end

  # lib/form.rb reads every colon name inside a function's #{...} as a
  # colon field, not only the first.
  def test_a_colon_on_a_checkbox_anywhere_in_a_function_fails
    calc = swap(MAIL, %(--steps "\#{:steps}"), %(--n \#{calc(:n + :steps)}))
    assert_equal [%(script: \#{:steps} names a checkbox, whose line drops when nothing is chosen, colon or not (#184))],
                 problems(calc)
  end

  def test_a_colon_on_a_text_field_passes
    f = <<~YAML
      form:
        seed:
          widget: text
          value: ""
      script: |
        --seed "\#{:seed}"
    YAML
    assert_empty problems(f)
  end
end
