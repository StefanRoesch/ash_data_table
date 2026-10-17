defmodule AshDataTable.Text do
  @moduledoc false
  # The one place where a table's texts become what a person reads. Three
  # kinds of text pass through here:
  #
  #   * the table's own (`t/2`, `n/2`): messages of the Gettext domain
  #     `ash_data_table`, written in English, looked up in the backend the host
  #     names with `config :ash_data_table, gettext_backend: …`, else in
  #     `AshDataTable.Gettext`, which has no translations;
  #
  #   * the resource's wording that the table shows (`label/1`): column
  #     labels, enum labels, questions. They are looked up in the same domain
  #     of the same backend, and come back as they are when it has no entry;
  #
  #   * the messages of the resource's actions (`error/1`): given to the
  #     function the host names with `config :ash_data_table, translate_error: …`,
  #     which is the `translate_error/1` of a Phoenix app's core components;
  #     without one, the message with its variables filled in.
  #
  # Both settings are read when a text is needed, as the layout is, so that a
  # host changes them without compiling this library again.
  #
  # The data layer makes no words: it says what it has to say as a message
  # (`t:message/0`), and the drawing and the live layer's replies turn it into
  # text with `say/1`, in the LiveView's process, whose locale it is.

  # For the `*_noop` macros alone: they mark the messages for
  # `mix gettext.extract`. Nothing is looked up in this backend directly.
  use Gettext, backend: AshDataTable.Gettext

  @domain "ash_data_table"

  # the keys are the public list's (`AshDataTable.Messages`); a key that is
  # not in it is refused, so that the list says every text a table shows
  @type key :: AshDataTable.Messages.key()

  @plurals AshDataTable.Messages.plurals()

  @typedoc """
  A message, as the table's code passes it on until it is said: one of the
  data layer's (`t:AshDataTable.Errors.message/0`), or a text that is words
  already: a label of the model, which the live layer translates once as
  it builds the model for a person.
  """
  @type message :: AshDataTable.Errors.message() | String.t()

  @doc "What a message says, in the locale of the process that asks."
  @spec say(message) :: String.t()
  def say({:text, key, bindings}) when key in @plurals do
    {count, bindings} = Keyword.pop!(bindings, :count)
    n(key, count, said(bindings))
  end

  def say({:text, key, bindings}), do: t(key, said(bindings))
  def say({:ash, message, vars}), do: error({message, vars})
  def say({:label, text}), do: label(text)
  def say({:join, separator, messages}), do: Enum.map_join(messages, separator, &say/1)

  def say({:once, separator, messages}),
    do: messages |> Enum.map(&say/1) |> Enum.uniq() |> Enum.join(separator)

  def say(text) when is_binary(text), do: text

  @doc """
  Messages each once by what they say: one whose words another before it
  says already is left out, as a text that is shown twice would be.
  """
  @spec once([message]) :: [message]
  def once(messages), do: Enum.uniq_by(messages, &say/1)

  @doc """
  Messages with how many times each came up (what a run on a selection
  counts), each once by what it says: the counts of those that say the
  same are added up, in the place of the first.
  """
  @spec counted([{message, pos_integer}]) :: [{message, pos_integer}]
  def counted(counts) do
    counts
    |> Enum.reduce([], fn {message, count}, counted ->
      words = say(message)

      case Enum.find_index(counted, fn {known, _count, _message} -> known == words end) do
        nil ->
          [{words, count, message} | counted]

        at ->
          List.update_at(counted, at, fn {known, before, first} ->
            {known, before + count, first}
          end)
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {_words, count, message} -> {message, count} end)
  end

  defp said(bindings) do
    for {name, value} <- bindings, do: {name, if(message?(value), do: say(value), else: value)}
  end

  defp message?({:text, key, bindings}) when is_atom(key) and is_list(bindings), do: true
  defp message?({:ash, message, _vars}) when is_binary(message), do: true
  defp message?({:label, text}) when is_binary(text), do: true

  defp message?({joined, separator, messages})
       when joined in [:join, :once] and is_binary(separator) and is_list(messages),
       do: true

  defp message?(_value), do: false

  @doc "The text for `key`, with `%{name}` placeholders filled from `bindings`."
  @spec t(key, keyword) :: String.t()
  def t(key, bindings \\ []) do
    known!(key)
    Gettext.dgettext(backend(), @domain, msgid(key), Map.new(bindings))
  end

  @doc """
  The text for `key` in the plural form of `count`, which is bound as
  `%{count}`, with the other placeholders filled from `bindings`.
  """
  @spec n(key, non_neg_integer, keyword) :: String.t()
  def n(key, count, bindings \\ []) do
    known!(key)
    {singular, plural} = msgids(key)
    Gettext.dngettext(backend(), @domain, singular, plural, count, Map.new(bindings))
  end

  defp known!(key) do
    if not AshDataTable.Messages.key?(key) do
      raise ArgumentError,
            "#{inspect(key)} is no key of AshDataTable.Messages: a text a table shows is in its list"
    end
  end

  @doc "The locale the table's texts are said in, in this process: Gettext's, of its backend."
  @spec locale() :: String.t()
  def locale, do: Gettext.get_locale(backend())

  # what a filter change found, for the live region
  defp msgids(:results), do: dngettext_noop("ash_data_table", "1 result", "%{count} results")
  # the total of a table that does not know where its page lies in it
  defp msgids(:records), do: dngettext_noop("ash_data_table", "1 record", "%{count} records")

  # what is asked before an action runs on the selected rows
  defp msgids(:bulk_question),
    do:
      dngettext_noop(
        "ash_data_table",
        "Run “%{action}” on 1 record?",
        "Run “%{action}” on %{count} records?"
      )

  # the same for an action with a question of its own, which comes first
  defp msgids(:bulk_confirm),
    do:
      dngettext_noop(
        "ash_data_table",
        "%{question} 1 record is selected.",
        "%{question} %{count} records are selected."
      )

  # the heading of the panel of an action that runs on the selected rows
  defp msgids(:bulk_on),
    do: dngettext_noop("ash_data_table", "%{action}: 1 record", "%{action}: %{count} records")

  @doc """
  A text of the resource's as the table shows it: translated when the
  `ash_data_table` domain of the host's backend has it as a message, else as it is.
  """
  @spec label(String.t()) :: String.t()
  def label(""), do: ""
  def label(text) when is_binary(text), do: Gettext.dgettext(backend(), @domain, text)

  # A message of an action, with its variables: through the host's error
  # translator when one is configured, else with the variables filled in.
  defp error({message, vars}) when is_binary(message) do
    vars = vars(vars)

    case Application.get_env(:ash_data_table, :translate_error) do
      nil ->
        Enum.reduce(vars, message, fn {name, value}, message ->
          String.replace(message, "%{#{name}}", to_string(value))
        end)

      {module, function} when is_atom(module) and is_atom(function) ->
        to_string(apply(module, function, [{message, vars}]))
    end
  end

  # The variables of an error as the bindings of a message: by name, with
  # values that can be written out. Numbers stay numbers, for plural forms.
  defp vars(vars) do
    for {name, value} <- List.wrap(if(is_map(vars), do: Map.to_list(vars), else: vars)),
        is_atom(name) or is_binary(name) do
      {name, var(value)}
    end
  end

  defp var(value) when is_binary(value) or is_number(value), do: value
  defp var(value) when is_atom(value), do: to_string(value)
  defp var(value), do: inspect(value)

  defp backend, do: Application.get_env(:ash_data_table, :gettext_backend, AshDataTable.Gettext)

  defp msgid(:no_records), do: dgettext_noop("ash_data_table", "No records")

  defp msgid(:read_failed),
    do: dgettext_noop("ash_data_table", "The records could not be loaded.")

  defp msgid(:not_allowed),
    do: dgettext_noop("ash_data_table", "You are not allowed to see these records.")

  # names the table, so that two tables in a page have two landmarks
  defp msgid(:pagination), do: dgettext_noop("ash_data_table", "Pagination: %{table}")
  defp msgid(:previous), do: dgettext_noop("ash_data_table", "Previous")
  defp msgid(:next), do: dgettext_noop("ash_data_table", "Next")
  defp msgid(:page), do: dgettext_noop("ash_data_table", "Page %{page}")
  defp msgid(:go_to_page), do: dgettext_noop("ash_data_table", "Go to page %{page}")
  defp msgid(:rows_per_page), do: dgettext_noop("ash_data_table", "Rows per page")
  defp msgid(:range), do: dgettext_noop("ash_data_table", "%{from}–%{to}")
  defp msgid(:range_of_total), do: dgettext_noop("ash_data_table", "%{from}–%{to} of %{total}")
  defp msgid(:yes), do: dgettext_noop("ash_data_table", "Yes")
  defp msgid(:no), do: dgettext_noop("ash_data_table", "No")
  defp msgid(:not_available), do: dgettext_noop("ash_data_table", "Not available")
  defp msgid(:operator_contains), do: dgettext_noop("ash_data_table", "contains")
  defp msgid(:operator_equals), do: dgettext_noop("ash_data_table", "equals")
  defp msgid(:operator_starts_with), do: dgettext_noop("ash_data_table", "starts with")
  defp msgid(:operator_is_empty), do: dgettext_noop("ash_data_table", "is empty")
  defp msgid(:operator_greater_than), do: dgettext_noop("ash_data_table", "greater than")
  defp msgid(:operator_less_than), do: dgettext_noop("ash_data_table", "less than")
  defp msgid(:operator_at_least), do: dgettext_noop("ash_data_table", "at least")
  defp msgid(:operator_at_most), do: dgettext_noop("ash_data_table", "at most")
  defp msgid(:operator_on), do: dgettext_noop("ash_data_table", "on")
  defp msgid(:operator_before), do: dgettext_noop("ash_data_table", "before")
  defp msgid(:operator_after), do: dgettext_noop("ash_data_table", "after")
  defp msgid(:operator_is), do: dgettext_noop("ash_data_table", "is")
  defp msgid(:operator_any_of), do: dgettext_noop("ash_data_table", "is any of")
  defp msgid(:operator_none_of), do: dgettext_noop("ash_data_table", "is none of")
  defp msgid(:operator_between), do: dgettext_noop("ash_data_table", "between")
  # the two inputs of a range: what stands before each, and its name
  defp msgid(:range_from), do: dgettext_noop("ash_data_table", "from")
  defp msgid(:range_to), do: dgettext_noop("ash_data_table", "to")
  defp msgid(:filter_from), do: dgettext_noop("ash_data_table", "Filter %{column}, from")
  defp msgid(:filter_to), do: dgettext_noop("ash_data_table", "Filter %{column}, to")
  # what the button of a filter for several values says of more than one
  defp msgid(:values_chosen), do: dgettext_noop("ash_data_table", "%{count} selected")
  defp msgid(:any), do: dgettext_noop("ash_data_table", "Any")
  defp msgid(:filter), do: dgettext_noop("ash_data_table", "Filter %{column}")
  defp msgid(:filter_operator), do: dgettext_noop("ash_data_table", "How to filter %{column}")
  defp msgid(:invalid_filter), do: dgettext_noop("ash_data_table", "Not a valid value")
  defp msgid(:clear_filter), do: dgettext_noop("ash_data_table", "Clear the %{column} filter")
  defp msgid(:clear_filters), do: dgettext_noop("ash_data_table", "Clear filters")

  defp msgid(:changed_records),
    do: dgettext_noop("ash_data_table", "There are new or changed records.")

  defp msgid(:read_again), do: dgettext_noop("ash_data_table", "Read again")
  defp msgid(:results_updated), do: dgettext_noop("ash_data_table", "Results updated")

  defp msgid(:record_gone),
    do: dgettext_noop("ash_data_table", "This record is no longer available.")

  defp msgid(:error_on_field), do: dgettext_noop("ash_data_table", "%{field}: %{message}")

  defp msgid(:edit_not_allowed),
    do: dgettext_noop("ash_data_table", "You are not allowed to change this.")

  defp msgid(:save_failed), do: dgettext_noop("ash_data_table", "This could not be saved.")

  # a wall time that the clocks of the page's zone skip, when they go forward
  defp msgid(:no_such_time),
    do: dgettext_noop("ash_data_table", "This time does not exist in %{zone}.")

  defp msgid(:not_saved),
    do: dgettext_noop("ash_data_table", "%{column} was not saved: %{message}")

  defp msgid(:cancel), do: dgettext_noop("ash_data_table", "Cancel")
  defp msgid(:confirm), do: dgettext_noop("ash_data_table", "Confirm")
  # names the column of the expanders, and each expander
  defp msgid(:related_records), do: dgettext_noop("ash_data_table", "Related records")
  # in a nested table whose first read is on its way
  defp msgid(:loading), do: dgettext_noop("ash_data_table", "Loading…")

  # in a nested table whose read was refused, where the destination's table
  # does not say `on_forbidden :message`
  defp msgid(:records_not_available),
    do: dgettext_noop("ash_data_table", "These records are not available.")

  # on the link of a nested table that opens its records on the page of
  # their own resource; the second names the table, for a screen reader
  defp msgid(:full_view), do: dgettext_noop("ash_data_table", "Open in full view")
  defp msgid(:full_view_of), do: dgettext_noop("ash_data_table", "Open in full view: %{table}")

  # over a table limited to the records related to one record: what that
  # record is called, and its relationship ("Write the report: Comments")
  defp msgid(:related_heading), do: dgettext_noop("ash_data_table", "%{record}: %{relationship}")
  # the control that takes the limit away
  defp msgid(:show_all_records), do: dgettext_noop("ash_data_table", "Show all records")

  # the header of the column that holds the row actions
  defp msgid(:actions), do: dgettext_noop("ash_data_table", "Actions")
  # the create button, and the heading of its panel: "New task"
  defp msgid(:new_record), do: dgettext_noop("ash_data_table", "New %{name}")
  # the buttons of the action panel that run a row action and a create action
  defp msgid(:run), do: dgettext_noop("ash_data_table", "Run")
  defp msgid(:create), do: dgettext_noop("ash_data_table", "Create")
  # the heading of the panel of a row action: the action and the record
  defp msgid(:action_on), do: dgettext_noop("ash_data_table", "%{action}: %{record}")
  # read out when an action has run, and when a record was created
  defp msgid(:action_done), do: dgettext_noop("ash_data_table", "%{action}: done")
  # shown, and read out, when a generic action has run and returned a value
  # that can be said in a word or a line: the action, and the value
  defp msgid(:action_result), do: dgettext_noop("ash_data_table", "%{action}: %{result}")
  defp msgid(:created), do: dgettext_noop("ash_data_table", "%{name} created")
  # read out when an action failed, with the action's message
  defp msgid(:action_not_done),
    do: dgettext_noop("ash_data_table", "%{action} failed: %{message}")

  defp msgid(:action_not_allowed),
    do: dgettext_noop("ash_data_table", "You are not allowed to do this.")

  defp msgid(:action_failed), do: dgettext_noop("ash_data_table", "This could not be done.")

  # the editor of an array: its button that adds a value, what each value's
  # control is called ("Tags 2"), and what the button that takes it away is
  defp msgid(:add_value), do: dgettext_noop("ash_data_table", "Add value")
  defp msgid(:value_position), do: dgettext_noop("ash_data_table", "%{column} %{position}")
  defp msgid(:remove_value), do: dgettext_noop("ash_data_table", "Remove %{column} %{position}")

  # what the box of a row is called, and the one in the header that stands
  # for the rows of the page
  defp msgid(:select_row), do: dgettext_noop("ash_data_table", "Select row")
  defp msgid(:select_page), do: dgettext_noop("ash_data_table", "Select all rows of this page")
  # names the line above the grid that says what is selected
  defp msgid(:selected_rows), do: dgettext_noop("ash_data_table", "Selected rows")
  # on that line: how many rows are selected. The count is put in by the
  # table's hook, which is why it has no plural forms.
  defp msgid(:selected), do: dgettext_noop("ash_data_table", "%{count} selected")

  # every record the filters match is selected, on this page and on the
  # others; without a number where the read action does not count
  defp msgid(:all_selected),
    do: dgettext_noop("ash_data_table", "All %{count} that match are selected")

  defp msgid(:all_selected_uncounted),
    do: dgettext_noop("ash_data_table", "All that match are selected")

  # the button that selects them, once every row of the page is selected
  defp msgid(:select_all), do: dgettext_noop("ash_data_table", "Select all %{count} that match")
  defp msgid(:select_all_uncounted), do: dgettext_noop("ash_data_table", "Select all that match")
  defp msgid(:clear_selection), do: dgettext_noop("ash_data_table", "Clear selection")

  # an action on every record that matches, where the table has no number:
  # the question, the same after a question of the action's own, and the
  # heading of the panel
  defp msgid(:bulk_question_all),
    do: dgettext_noop("ash_data_table", "Run “%{action}” on all records that match?")

  defp msgid(:bulk_confirm_all),
    do: dgettext_noop("ash_data_table", "%{question} All records that match are selected.")

  defp msgid(:bulk_on_all),
    do: dgettext_noop("ash_data_table", "%{action}: all records that match")

  # what became of an action that ran on the selected rows: on how many
  # records it ran and on how many it did not, and each message of the
  # action with the number of records it is about
  defp msgid(:bulk_done), do: dgettext_noop("ash_data_table", "%{action}: %{done} done.")

  defp msgid(:bulk_not_done),
    do: dgettext_noop("ash_data_table", "%{action}: %{done} done, %{failed} not done.")

  # the selection changed after the question before such an action was
  # asked: nothing ran
  defp msgid(:bulk_selection_changed),
    do:
      dgettext_noop(
        "ash_data_table",
        "Nothing was run: the selection changed after the question was asked."
      )

  defp msgid(:bulk_failure), do: dgettext_noop("ash_data_table", "%{message} (%{count})")

  # the picker, in which a person chooses a related record: its button that
  # takes the selected row, on the field of the action panel the button that
  # opens it, and its button that chooses no record
  defp msgid(:choose), do: dgettext_noop("ash_data_table", "Choose")
  defp msgid(:choose_none), do: dgettext_noop("ash_data_table", "None")
  # its heading: the column the record is chosen for, and what one record of
  # the table it is chosen from is called ("Assignee: choose user")
  defp msgid(:choose_for), do: dgettext_noop("ash_data_table", "%{column}: choose %{name}")
  # said, to a screen reader, of a field of the action panel that has no
  # control to say it of
  defp msgid(:required), do: dgettext_noop("ash_data_table", "required")

  # one field of a value that is made of fields (an embedded resource, a
  # map), as its cell shows it: what the field is called, and its value
  defp msgid(:field_value), do: dgettext_noop("ash_data_table", "%{field}: %{value}")
  # the button of the panel in which such a cell is edited
  defp msgid(:save), do: dgettext_noop("ash_data_table", "Save")
  # In that panel, and in the action panel: what the button is called that
  # takes such a value away, where it is not one of a list. And what the
  # button is called that takes a related record out of a field that holds
  # several: by what the record is called ("Remove ops").
  defp msgid(:remove_group), do: dgettext_noop("ash_data_table", "Remove %{column}")

  # in place of the rows, while an argument that the read action requires is
  # empty: what the argument is called, or what they are called, with commas
  defp msgid(:fill_in), do: dgettext_noop("ash_data_table", "Fill in %{argument} to see records.")

  # what an argument is called that a column asks for: the column, and the
  # argument ("Price in: Currency")
  defp msgid(:argument_of), do: dgettext_noop("ash_data_table", "%{column}: %{argument}")

  # in the action panel, at the field of a union: what the choice of its
  # kind is called
  defp msgid(:kind), do: dgettext_noop("ash_data_table", "Kind")

  # At the field of an argument that takes a file, what LiveView says of a
  # file it does not take: larger than the limit, which is said as a size
  # ("8 MB"); of a type the field does not accept; and a file that did not
  # arrive.
  defp msgid(:upload_too_large),
    do: dgettext_noop("ash_data_table", "The file is too large. The limit is %{limit}.")

  defp msgid(:upload_not_accepted),
    do: dgettext_noop("ash_data_table", "This type of file is not accepted.")

  defp msgid(:upload_failed),
    do: dgettext_noop("ash_data_table", "The file could not be uploaded.")

  # In a cell of a sensitive column: what a screen reader says in place of
  # the mask; what the cell's button says, and what it is called, with the
  # column, before and after the value is shown.
  defp msgid(:hidden_value), do: dgettext_noop("ash_data_table", "Hidden")
  defp msgid(:show), do: dgettext_noop("ash_data_table", "Show")
  defp msgid(:hide), do: dgettext_noop("ash_data_table", "Hide")
  defp msgid(:show_value), do: dgettext_noop("ash_data_table", "Show %{column}")
  defp msgid(:hide_value), do: dgettext_noop("ash_data_table", "Hide %{column}")

  # At a sensitive value that can be emptied, in the editor of its cell and
  # at its field of the action panel: the button that empties it, and what
  # it is called, with the column. In the panel the value is emptied when
  # the action runs: until then the field says so, and the button takes it
  # back.
  defp msgid(:clear), do: dgettext_noop("ash_data_table", "Clear")
  defp msgid(:clear_value), do: dgettext_noop("ash_data_table", "Clear %{column}")
  defp msgid(:keep), do: dgettext_noop("ash_data_table", "Keep")
  defp msgid(:keep_value), do: dgettext_noop("ash_data_table", "Keep %{column}")
  defp msgid(:will_be_cleared), do: dgettext_noop("ash_data_table", "Will be cleared.")

  # What the handle at the end of a column's header is called, with the
  # column: a person drags it, or moves it with the arrow keys, to make the
  # column wider or narrower.
  defp msgid(:resize_column), do: dgettext_noop("ash_data_table", "Resize %{column}")

  # Hiding columns. "Columns" is the button above the grid and the name of
  # its list. With columns hidden the button says how many, and how many of
  # those the rows are filtered and sorted by: "Columns (2 hidden, 1
  # filtered)". The parts are put together in the browser, which alone knows
  # what is hidden, with a comma between them.
  defp msgid(:columns), do: dgettext_noop("ash_data_table", "Columns")
  defp msgid(:columns_with), do: dgettext_noop("ash_data_table", "Columns (%{details})")
  defp msgid(:columns_hidden), do: dgettext_noop("ash_data_table", "%{count} hidden")
  defp msgid(:columns_filtered), do: dgettext_noop("ash_data_table", "%{count} filtered")
  defp msgid(:columns_sorted), do: dgettext_noop("ash_data_table", "%{count} sorted")
  # at the box of a hidden column in the list, in brackets after its name
  defp msgid(:column_filtered), do: dgettext_noop("ash_data_table", "filtered")
  defp msgid(:column_sorted), do: dgettext_noop("ash_data_table", "sorted")
  defp msgid(:column_filtered_sorted), do: dgettext_noop("ash_data_table", "filtered, sorted")
  # read out when a column is hidden, and when it is shown again
  defp msgid(:column_hidden), do: dgettext_noop("ash_data_table", "%{column} hidden")
  defp msgid(:column_shown), do: dgettext_noop("ash_data_table", "%{column} shown")

  # In the footer row, under a column with a summary: what the number is,
  # before the number ("Sum 1240"). And what is read out in place of a
  # number that cannot be shown to this person, where the cell shows "–".
  defp msgid(:summary_count), do: dgettext_noop("ash_data_table", "Count")
  defp msgid(:summary_sum), do: dgettext_noop("ash_data_table", "Sum")
  defp msgid(:summary_avg), do: dgettext_noop("ash_data_table", "Average")
  defp msgid(:summary_min), do: dgettext_noop("ash_data_table", "Min")
  defp msgid(:summary_max), do: dgettext_noop("ash_data_table", "Max")
end
