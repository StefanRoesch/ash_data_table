defmodule AshDataTable.Messages do
  # Every message a table says, by key: the names of its values and its
  # English text, the msgid of the Gettext domain `ash_data_table` (and the
  # plural msgid of a key with a form per number). The one list
  # `AshDataTable.Text` takes keys and msgids from, and what a kit is told a
  # part shows (`AshDataTable.Kit`, the design note of stage 7, D23).
  #
  # The `*_noop` macros mark the msgids for `mix gettext.extract`, which
  # writes them into `priv/gettext/ash_data_table.pot`. Nothing is looked up
  # in this backend: `AshDataTable.Text` looks up in the host's.
  use Gettext, backend: AshDataTable.Gettext

  @messages [
    no_records: {[], dgettext_noop("ash_data_table", "No records")},
    read_failed: {[], dgettext_noop("ash_data_table", "The records could not be loaded.")},
    not_allowed:
      {[], dgettext_noop("ash_data_table", "You are not allowed to see these records.")},
    # names the table, so that two tables in a page have two landmarks
    pagination: {[:table], dgettext_noop("ash_data_table", "Pagination: %{table}")},
    previous: {[], dgettext_noop("ash_data_table", "Previous")},
    next: {[], dgettext_noop("ash_data_table", "Next")},
    page: {[:page], dgettext_noop("ash_data_table", "Page %{page}")},
    go_to_page: {[:page], dgettext_noop("ash_data_table", "Go to page %{page}")},
    rows_per_page: {[], dgettext_noop("ash_data_table", "Rows per page")},
    range: {[:from, :to], dgettext_noop("ash_data_table", "%{from}–%{to}")},
    range_of_total:
      {[:from, :to, :total], dgettext_noop("ash_data_table", "%{from}–%{to} of %{total}")},
    # the total of a table that does not know where its page lies in it
    records: {[:count], dngettext_noop("ash_data_table", "1 record", "%{count} records")},
    # what a filter change found, for the live region
    results: {[:count], dngettext_noop("ash_data_table", "1 result", "%{count} results")},
    yes: {[], dgettext_noop("ash_data_table", "Yes")},
    no: {[], dgettext_noop("ash_data_table", "No")},
    not_available: {[], dgettext_noop("ash_data_table", "Not available")},
    operator_contains: {[], dgettext_noop("ash_data_table", "contains")},
    operator_equals: {[], dgettext_noop("ash_data_table", "equals")},
    operator_starts_with: {[], dgettext_noop("ash_data_table", "starts with")},
    operator_is_empty: {[], dgettext_noop("ash_data_table", "is empty")},
    operator_greater_than: {[], dgettext_noop("ash_data_table", "greater than")},
    operator_less_than: {[], dgettext_noop("ash_data_table", "less than")},
    operator_at_least: {[], dgettext_noop("ash_data_table", "at least")},
    operator_at_most: {[], dgettext_noop("ash_data_table", "at most")},
    operator_on: {[], dgettext_noop("ash_data_table", "on")},
    operator_before: {[], dgettext_noop("ash_data_table", "before")},
    operator_after: {[], dgettext_noop("ash_data_table", "after")},
    operator_is: {[], dgettext_noop("ash_data_table", "is")},
    operator_any_of: {[], dgettext_noop("ash_data_table", "is any of")},
    operator_none_of: {[], dgettext_noop("ash_data_table", "is none of")},
    operator_between: {[], dgettext_noop("ash_data_table", "between")},
    filter_from: {[:column], dgettext_noop("ash_data_table", "Filter %{column}, from")},
    filter_to: {[:column], dgettext_noop("ash_data_table", "Filter %{column}, to")},
    # the two inputs of a range: what stands before each, and its name
    range_from: {[], dgettext_noop("ash_data_table", "from")},
    range_to: {[], dgettext_noop("ash_data_table", "to")},
    # what the button of a filter for several values says of more than one
    values_chosen:
      {[:count], dngettext_noop("ash_data_table", "1 selected", "%{count} selected")},
    any: {[], dgettext_noop("ash_data_table", "Any")},
    filter: {[:column], dgettext_noop("ash_data_table", "Filter %{column}")},
    filter_operator: {[:column], dgettext_noop("ash_data_table", "How to filter %{column}")},
    invalid_filter: {[], dgettext_noop("ash_data_table", "Not a valid value")},
    clear_filter: {[:column], dgettext_noop("ash_data_table", "Clear the %{column} filter")},
    clear_filters: {[], dgettext_noop("ash_data_table", "Clear filters")},
    changed_records: {[], dgettext_noop("ash_data_table", "There are new or changed records.")},
    read_again: {[], dgettext_noop("ash_data_table", "Read again")},
    results_updated: {[], dgettext_noop("ash_data_table", "Results updated")},
    record_gone: {[], dgettext_noop("ash_data_table", "This record is no longer available.")},
    error_on_field: {[:field, :message], dgettext_noop("ash_data_table", "%{field}: %{message}")},
    edit_not_allowed:
      {[], dgettext_noop("ash_data_table", "You are not allowed to change this.")},
    save_failed: {[], dgettext_noop("ash_data_table", "This could not be saved.")},
    # a wall time that the clocks of the page's zone skip, when they go forward
    no_such_time:
      {[:zone], dgettext_noop("ash_data_table", "This time does not exist in %{zone}.")},
    not_saved:
      {[:column, :message],
       dgettext_noop("ash_data_table", "%{column} was not saved: %{message}")},
    cancel: {[], dgettext_noop("ash_data_table", "Cancel")},
    confirm: {[], dgettext_noop("ash_data_table", "Confirm")},
    # names the column of the expanders, and each expander
    related_records: {[], dgettext_noop("ash_data_table", "Related records")},
    # in a nested table whose first read is on its way
    loading: {[], dgettext_noop("ash_data_table", "Loading…")},
    # in a nested table whose read was refused, where the destination's table
    # does not say `on_forbidden :message`
    records_not_available:
      {[], dgettext_noop("ash_data_table", "These records are not available.")},
    # on the link of a nested table that opens its records on the page of
    # their own resource; the second names the table, for a screen reader
    full_view: {[], dgettext_noop("ash_data_table", "Open in full view")},
    full_view_of: {[:table], dgettext_noop("ash_data_table", "Open in full view: %{table}")},
    # over a table limited to the records related to one record: what that
    # record is called, and its relationship ("Write the report: Comments")
    related_heading:
      {[:record, :relationship], dgettext_noop("ash_data_table", "%{record}: %{relationship}")},
    # the control that takes the limit away
    show_all_records: {[], dgettext_noop("ash_data_table", "Show all records")},
    # the header of the column that holds the row actions
    actions: {[], dgettext_noop("ash_data_table", "Actions")},
    # the create button, and the heading of its panel: "New task"
    new_record: {[:name], dgettext_noop("ash_data_table", "New %{name}")},
    # the buttons of the action panel that run a row action and a create action
    run: {[], dgettext_noop("ash_data_table", "Run")},
    create: {[], dgettext_noop("ash_data_table", "Create")},
    # the heading of the panel of a row action: the action and the record
    action_on: {[:action, :record], dgettext_noop("ash_data_table", "%{action}: %{record}")},
    # read out when an action has run, and when a record was created
    action_done: {[:action], dgettext_noop("ash_data_table", "%{action}: done")},
    # shown, and read out, when a generic action has run and returned a value
    # that can be said in a word or a line: the action, and the value
    action_result: {[:action, :result], dgettext_noop("ash_data_table", "%{action}: %{result}")},
    created: {[:name], dgettext_noop("ash_data_table", "%{name} created")},
    # read out when an action failed, with the action's message
    action_not_done:
      {[:action, :message], dgettext_noop("ash_data_table", "%{action} failed: %{message}")},
    action_not_allowed: {[], dgettext_noop("ash_data_table", "You are not allowed to do this.")},
    action_failed: {[], dgettext_noop("ash_data_table", "This could not be done.")},
    # the editor of an array: its button that adds a value, what each value's
    # control is called ("Tags 2"), and what the button that takes it away is
    add_value: {[], dgettext_noop("ash_data_table", "Add value")},
    value_position:
      {[:column, :position], dgettext_noop("ash_data_table", "%{column} %{position}")},
    remove_value:
      {[:column, :position], dgettext_noop("ash_data_table", "Remove %{column} %{position}")},
    # what the box of a row is called, and the one in the header that stands
    # for the rows of the page
    select_row: {[], dgettext_noop("ash_data_table", "Select row")},
    select_page: {[], dgettext_noop("ash_data_table", "Select all rows of this page")},
    # names the line above the grid that says what is selected
    selected_rows: {[], dgettext_noop("ash_data_table", "Selected rows")},
    # on that line: how many rows are selected
    selected: {[:count], dngettext_noop("ash_data_table", "1 selected", "%{count} selected")},
    # every record the filters match is selected, on this page and on the
    # others; without a number where the read action does not count
    all_selected:
      {[:count], dgettext_noop("ash_data_table", "All %{count} that match are selected")},
    all_selected_uncounted: {[], dgettext_noop("ash_data_table", "All that match are selected")},
    # the button that selects them, once every row of the page is selected
    select_all: {[:count], dgettext_noop("ash_data_table", "Select all %{count} that match")},
    select_all_uncounted: {[], dgettext_noop("ash_data_table", "Select all that match")},
    clear_selection: {[], dgettext_noop("ash_data_table", "Clear selection")},
    # what is asked before an action runs on the selected rows
    bulk_question:
      {[:count, :action],
       dngettext_noop(
         "ash_data_table",
         "Run “%{action}” on 1 record?",
         "Run “%{action}” on %{count} records?"
       )},
    # the same for an action with a question of its own, which comes first
    bulk_confirm:
      {[:count, :question],
       dngettext_noop(
         "ash_data_table",
         "%{question} 1 record is selected.",
         "%{question} %{count} records are selected."
       )},
    # the heading of the panel of an action that runs on the selected rows
    bulk_on:
      {[:count, :action],
       dngettext_noop("ash_data_table", "%{action}: 1 record", "%{action}: %{count} records")},
    # an action on every record that matches, where the table has no number:
    # the question, the same after a question of the action's own, and the
    # heading of the panel
    bulk_question_all:
      {[:action], dgettext_noop("ash_data_table", "Run “%{action}” on all records that match?")},
    bulk_confirm_all:
      {[:question],
       dgettext_noop("ash_data_table", "%{question} All records that match are selected.")},
    bulk_on_all:
      {[:action], dgettext_noop("ash_data_table", "%{action}: all records that match")},
    # what became of an action that ran on the selected rows: on how many
    # records it ran and on how many it did not, and each message of the
    # action with the number of records it is about
    bulk_done: {[:action, :done], dgettext_noop("ash_data_table", "%{action}: %{done} done.")},
    bulk_not_done:
      {[:action, :done, :failed],
       dgettext_noop("ash_data_table", "%{action}: %{done} done, %{failed} not done.")},
    # the selection changed after the question before such an action was
    # asked: nothing ran
    bulk_selection_changed:
      {[],
       dgettext_noop(
         "ash_data_table",
         "Nothing was run: the selection changed after the question was asked."
       )},
    bulk_failure: {[:message, :count], dgettext_noop("ash_data_table", "%{message} (%{count})")},
    # the picker, in which a person chooses a related record: its button that
    # takes the selected row, on the field of the action panel the button that
    # opens it, and its button that chooses no record
    choose: {[], dgettext_noop("ash_data_table", "Choose")},
    choose_none: {[], dgettext_noop("ash_data_table", "None")},
    # its heading: the column the record is chosen for, and what one record of
    # the table it is chosen from is called ("Assignee: choose user")
    choose_for: {[:column, :name], dgettext_noop("ash_data_table", "%{column}: choose %{name}")},
    # said, to a screen reader, of a field of the action panel that has no
    # control to say it of
    required: {[], dgettext_noop("ash_data_table", "required")},
    # one field of a value that is made of fields (an embedded resource, a
    # map), as its cell shows it: what the field is called, and its value
    field_value: {[:field, :value], dgettext_noop("ash_data_table", "%{field}: %{value}")},
    # the button of the panel in which such a cell is edited
    save: {[], dgettext_noop("ash_data_table", "Save")},
    # In that panel, and in the action panel: what the button is called that
    # takes such a value away, where it is not one of a list. And what the
    # button is called that takes a related record out of a field that holds
    # several: by what the record is called ("Remove ops").
    remove_group: {[:column], dgettext_noop("ash_data_table", "Remove %{column}")},
    # in place of the rows, while an argument that the read action requires is
    # empty: what the argument is called, or what they are called, with commas
    fill_in:
      {[:argument], dgettext_noop("ash_data_table", "Fill in %{argument} to see records.")},
    # what an argument is called that a column asks for: the column, and the
    # argument ("Price in: Currency")
    argument_of:
      {[:column, :argument], dgettext_noop("ash_data_table", "%{column}: %{argument}")},
    # in the action panel, at the field of a union: what the choice of its
    # kind is called
    kind: {[], dgettext_noop("ash_data_table", "Kind")},
    # At the field of an argument that takes a file, what LiveView says of a
    # file it does not take: larger than the limit, which is said as a size
    # ("8 MB"); of a type the field does not accept; and a file that did not
    # arrive.
    upload_too_large:
      {[:limit], dgettext_noop("ash_data_table", "The file is too large. The limit is %{limit}.")},
    upload_not_accepted:
      {[], dgettext_noop("ash_data_table", "This type of file is not accepted.")},
    upload_failed: {[], dgettext_noop("ash_data_table", "The file could not be uploaded.")},
    # In a cell of a sensitive column: what a screen reader says in place of
    # the mask; what the cell's button says, and what it is called, with the
    # column, before and after the value is shown.
    hidden_value: {[], dgettext_noop("ash_data_table", "Hidden")},
    show: {[], dgettext_noop("ash_data_table", "Show")},
    hide: {[], dgettext_noop("ash_data_table", "Hide")},
    show_value: {[:column], dgettext_noop("ash_data_table", "Show %{column}")},
    hide_value: {[:column], dgettext_noop("ash_data_table", "Hide %{column}")},
    # At a sensitive value that can be emptied, in the editor of its cell and
    # at its field of the action panel: the button that empties it, and what
    # it is called, with the column. In the panel the value is emptied when
    # the action runs: until then the field says so, and the button takes it
    # back.
    clear: {[], dgettext_noop("ash_data_table", "Clear")},
    clear_value: {[:column], dgettext_noop("ash_data_table", "Clear %{column}")},
    keep: {[], dgettext_noop("ash_data_table", "Keep")},
    keep_value: {[:column], dgettext_noop("ash_data_table", "Keep %{column}")},
    will_be_cleared: {[], dgettext_noop("ash_data_table", "Will be cleared.")},
    # What the handle at the end of a column's header is called, with the
    # column: a person drags it, or moves it with the arrow keys, to make the
    # column wider or narrower.
    resize_column: {[:column], dgettext_noop("ash_data_table", "Resize %{column}")},
    # Hiding columns. "Columns" is the button above the grid and the name of
    # its list. With columns hidden the button says how many, and how many of
    # those the rows are filtered and sorted by: "Columns (2 hidden, 1
    # filtered)". Each part is said for every number it can be, up to the
    # number of columns, and the browser, which alone knows what is hidden,
    # takes the ones it needs and puts them together with a comma between.
    columns: {[], dgettext_noop("ash_data_table", "Columns")},
    columns_with: {[:details], dgettext_noop("ash_data_table", "Columns (%{details})")},
    columns_hidden: {[:count], dngettext_noop("ash_data_table", "1 hidden", "%{count} hidden")},
    columns_filtered:
      {[:count], dngettext_noop("ash_data_table", "1 filtered", "%{count} filtered")},
    columns_sorted: {[:count], dngettext_noop("ash_data_table", "1 sorted", "%{count} sorted")},
    # at the box of a hidden column in the list, in brackets after its name
    column_filtered: {[], dgettext_noop("ash_data_table", "filtered")},
    column_sorted: {[], dgettext_noop("ash_data_table", "sorted")},
    column_filtered_sorted: {[], dgettext_noop("ash_data_table", "filtered, sorted")},
    # read out when a column is hidden, and when it is shown again
    column_hidden: {[:column], dgettext_noop("ash_data_table", "%{column} hidden")},
    column_shown: {[:column], dgettext_noop("ash_data_table", "%{column} shown")},
    # In the footer row, under a column with a summary: what the number is,
    # before the number ("Sum 1240"). And what is read out in place of a
    # number that cannot be shown to this person, where the cell shows "–".
    summary_count: {[], dgettext_noop("ash_data_table", "Count")},
    summary_sum: {[], dgettext_noop("ash_data_table", "Sum")},
    summary_avg: {[], dgettext_noop("ash_data_table", "Average")},
    summary_min: {[], dgettext_noop("ash_data_table", "Min")},
    summary_max: {[], dgettext_noop("ash_data_table", "Max")}
  ]

  # what is no text of the table's own, but put together of others
  @made [label: [:text], join: [:separator, :messages], words: [:text]]

  @all Map.new(
         for(
           {key, {values, msgid}} <- @messages,
           do:
             {key,
              case msgid do
                {singular, plural} -> %{values: values, msgid: singular, msgid_plural: plural}
                singular -> %{values: values, msgid: singular, msgid_plural: nil}
              end}
         ) ++
           for(
             {key, values} <- @made,
             do: {key, %{values: values, msgid: nil, msgid_plural: nil}}
           )
       )

  @moduledoc """
  Every message a table says, by key: the names of its values and its
  English text. It is what a kit's part is given besides the finished text
  (`AshDataTable.Kit`), so that a kit that translates for itself (a React
  or Vue kit, an API client) finds every key here, as a Gettext msgid with
  its bindings.

  A message is `{key, values}`, `values` a map of the names below; a value
  may be a message itself. Each key's English text is its msgid in the
  Gettext domain `ash_data_table`, as the template
  `priv/gettext/ash_data_table.pot` of the package holds it; a key with a
  form per number has a plural msgid too, and `count` among its values.
  `all/0` gives them as data.

  Three keys are no text of the table's own:

    * `:label` (`text`) - the resource's own wording (a question of a
      column, the name of a relationship), translated as a column label is,
      in the `ash_data_table` domain;
    * `:join` (`separator`, `messages`) - several messages, each said, with
      the separator between them;
    * `:words` (`text`) - words already (a label of the model).

  What an action says (an Ash error) is passed on as Ash and AshPhoenix
  give it, `{message, vars}`: a string and a keyword list, which a host's
  `translate_error/1` takes.

  The keys, their values and their English text:

  #{Enum.map_join(@messages, "\n", fn {key, {names, msgid}} -> "  * `#{inspect(key)}`" <> if(names == [], do: "", else: " (" <> Enum.map_join(names, ", ", &"`#{&1}`") <> ")") <> " - " <> case msgid do
      {singular, plural} -> "\"#{singular}\", \"#{plural}\""
      singular -> "\"#{singular}\""
    end end)}
  """

  @typedoc "A key of the list."
  @type key :: atom

  @typedoc """
  What the list says of a key: the names of its `values`, its English text
  (`msgid`, nil for the three made keys) and, for a key with a form per
  number, the English plural (`msgid_plural`, else nil).
  """
  @type definition :: %{
          values: [atom],
          msgid: String.t() | nil,
          msgid_plural: String.t() | nil
        }

  @typedoc """
  A message: a key and its values, or an action's message and its
  variables as Ash gives them.
  """
  @type t :: {key, %{optional(atom) => term}} | {String.t(), keyword}

  @doc "Every key, with what the list says of it."
  @spec all() :: %{key => definition}
  def all, do: @all

  @doc "Whether `key` is a key of the list."
  @spec key?(term) :: boolean
  def key?(key), do: is_map_key(@all, key)

  @doc false
  # A message as the table's code holds it (`t:AshDataTable.Text.message/0`)
  # as a part is given it: the form of this module. Nil stays nil.
  def of(nil), do: nil

  def of({:text, key, bindings}),
    do: {key, Map.new(bindings, fn {name, value} -> {name, value(value)} end)}

  def of({:ash, message, vars}), do: {message, ash_vars(vars)}
  def of({:label, text}), do: {:label, %{text: text}}

  def of({:join, separator, messages}),
    do: {:join, %{separator: separator, messages: Enum.map(messages, &of/1)}}

  # each text once, as `AshDataTable.Text.say/1` says it
  def of({:once, separator, messages}),
    do:
      {:join,
       %{separator: separator, messages: messages |> AshDataTable.Text.once() |> Enum.map(&of/1)}}

  def of(text) when is_binary(text), do: {:words, %{text: text}}

  defp value({:text, key, bindings} = message) when is_atom(key) and is_list(bindings),
    do: of(message)

  defp value({:ash, message, _vars} = ash) when is_binary(message), do: of(ash)
  defp value({:label, text} = label) when is_binary(text), do: of(label)

  defp value({joined, separator, messages} = message)
       when joined in [:join, :once] and is_binary(separator) and is_list(messages),
       do: of(message)

  defp value(value), do: value

  defp ash_vars(vars) when is_map(vars), do: Map.to_list(vars)
  defp ash_vars(vars) when is_list(vars), do: vars
  defp ash_vars(_none), do: []
end
