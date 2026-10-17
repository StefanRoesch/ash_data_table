defmodule AshDataTable.Messages do
  # Every message a table says, by key, with the names of its values: the
  # one list `AshDataTable.Text` takes keys from, and what a kit is told a
  # part shows (`AshDataTable.Kit`, the design note of stage 7, D23).
  @keys [
    no_records: [],
    read_failed: [],
    not_allowed: [],
    pagination: [:table],
    previous: [],
    next: [],
    page: [:page],
    go_to_page: [:page],
    rows_per_page: [],
    range: [:from, :to],
    range_of_total: [:from, :to, :total],
    records: [:count],
    results: [:count],
    yes: [],
    no: [],
    not_available: [],
    operator_contains: [],
    operator_equals: [],
    operator_starts_with: [],
    operator_is_empty: [],
    operator_greater_than: [],
    operator_less_than: [],
    operator_at_least: [],
    operator_at_most: [],
    operator_on: [],
    operator_before: [],
    operator_after: [],
    operator_is: [],
    operator_any_of: [],
    operator_none_of: [],
    operator_between: [],
    filter_from: [:column],
    filter_to: [:column],
    range_from: [],
    range_to: [],
    values_chosen: [:count],
    any: [],
    filter: [:column],
    filter_operator: [:column],
    invalid_filter: [],
    clear_filter: [:column],
    clear_filters: [],
    changed_records: [],
    read_again: [],
    results_updated: [],
    record_gone: [],
    error_on_field: [:field, :message],
    edit_not_allowed: [],
    save_failed: [],
    no_such_time: [:zone],
    not_saved: [:column, :message],
    cancel: [],
    confirm: [],
    related_records: [],
    loading: [],
    records_not_available: [],
    full_view: [],
    full_view_of: [:table],
    related_heading: [:record, :relationship],
    show_all_records: [],
    actions: [],
    new_record: [:name],
    run: [],
    create: [],
    action_on: [:action, :record],
    action_done: [:action],
    action_result: [:action, :result],
    created: [:name],
    action_not_done: [:action, :message],
    action_not_allowed: [],
    action_failed: [],
    add_value: [],
    value_position: [:column, :position],
    remove_value: [:column, :position],
    select_row: [],
    select_page: [],
    selected_rows: [],
    selected: [:count],
    all_selected: [:count],
    all_selected_uncounted: [],
    select_all: [:count],
    select_all_uncounted: [],
    clear_selection: [],
    bulk_question: [:count, :action],
    bulk_confirm: [:count, :question],
    bulk_on: [:count, :action],
    bulk_question_all: [:action],
    bulk_confirm_all: [:question],
    bulk_on_all: [:action],
    bulk_done: [:action, :done],
    bulk_not_done: [:action, :done, :failed],
    bulk_selection_changed: [],
    bulk_failure: [:message, :count],
    choose: [],
    choose_none: [],
    choose_for: [:column, :name],
    required: [],
    field_value: [:field, :value],
    save: [],
    remove_group: [:column],
    fill_in: [:argument],
    argument_of: [:column, :argument],
    kind: [],
    upload_too_large: [:limit],
    upload_not_accepted: [],
    upload_failed: [],
    hidden_value: [],
    show: [],
    hide: [],
    show_value: [:column],
    hide_value: [:column],
    clear: [],
    clear_value: [:column],
    keep: [],
    keep_value: [:column],
    will_be_cleared: [],
    resize_column: [:column],
    columns: [],
    columns_with: [:details],
    columns_hidden: [:count],
    columns_filtered: [:count],
    columns_sorted: [:count],
    column_filtered: [],
    column_sorted: [],
    column_filtered_sorted: [],
    column_hidden: [:column],
    column_shown: [:column],
    summary_count: [],
    summary_sum: [],
    summary_avg: [],
    summary_min: [],
    summary_max: []
  ]

  # what is no text of the table's own, but put together of others
  @made [label: [:text], join: [:separator, :messages], words: [:text]]

  # the keys whose text has a form per number: `count` is among their values
  @plurals [:records, :results, :bulk_question, :bulk_confirm, :bulk_on]

  @moduledoc """
  Every message a table says, by key, with the names of its values: what
  a kit's part is given besides the finished text (`AshDataTable.Kit`), so
  that a kit that translates for itself (a React or Vue kit, an API client)
  finds every key here, as a Gettext msgid with its bindings.

  A message is `{key, values}`, `values` a map of the names below; a value
  may be a message itself. The English text of each key is in the
  template `priv/gettext/ash_data_table.pot` of the package (Gettext domain
  `ash_data_table`); the keys #{Enum.map_join(@plurals, ", ", &"`#{&1}`")}
  have a form per number, by `count`.

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

  The keys and their values:

  #{Enum.map_join(@keys ++ @made, "\n", fn {key, names} -> "  * `#{inspect(key)}`" <> if(names == [], do: "", else: " - " <> Enum.map_join(names, ", ", &"`#{&1}`")) end)}
  """

  @typedoc "A key of the list."
  @type key :: atom

  @typedoc """
  A message: a key and its values, or an action's message and its
  variables as Ash gives them.
  """
  @type t :: {key, %{optional(atom) => term}} | {String.t(), keyword}

  @known Map.new(@keys ++ @made)

  @doc "Every key, with the names of its values."
  @spec keys() :: %{key => [atom]}
  def keys, do: @known

  @doc "The keys whose text has a form per number (`count`)."
  @spec plurals() :: [key]
  def plurals, do: @plurals

  @doc "Whether `key` is a key of the list."
  @spec key?(term) :: boolean
  def key?(key), do: is_map_key(@known, key)

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

  def of({:once, separator, messages}),
    do: {:join, %{separator: separator, messages: messages |> Enum.map(&of/1) |> Enum.uniq()}}

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
