defmodule AshTable.Text do
  @moduledoc false
  # The one place where a table's texts become what a person reads. Three
  # kinds of text pass through here:
  #
  #   * the table's own (`t/2`, `n/2`): messages of the Gettext domain
  #     `ash_table`, written in English, looked up in the backend the host
  #     names with `config :ash_table, gettext_backend: …`, else in
  #     `AshTable.Gettext`, which has no translations;
  #
  #   * the resource's wording that the table shows (`label/1`): column
  #     labels, enum labels, questions. They are looked up in the same domain
  #     of the same backend, and come back as they are when it has no entry;
  #
  #   * the messages of the resource's actions (`error/1`): given to the
  #     function the host names with `config :ash_table, translate_error: …`,
  #     which is the `translate_error/1` of a Phoenix app's core components;
  #     without one, the message with its variables filled in.
  #
  # Both settings are read when a text is needed, as the layout is, so that a
  # host changes them without compiling this library again.

  # For the `*_noop` macros alone: they mark the messages for
  # `mix gettext.extract`. Nothing is looked up in this backend directly.
  use Gettext, backend: AshTable.Gettext

  @domain "ash_table"

  @type key ::
          :no_records
          | :read_failed
          | :not_allowed
          | :pagination
          | :previous
          | :next
          | :page
          | :go_to_page
          | :range
          | :range_of_total
          | :yes
          | :no
          | :not_available
          | :operator_contains
          | :operator_equals
          | :operator_starts_with
          | :operator_is_empty
          | :operator_greater_than
          | :operator_less_than
          | :operator_at_least
          | :operator_at_most
          | :operator_on
          | :operator_before
          | :operator_after
          | :operator_is
          | :any
          | :filter
          | :filter_operator
          | :invalid_filter
          | :clear_filter
          | :clear_filters
          | :results_updated
          | :record_gone
          | :error_on_field
          | :edit_not_allowed
          | :save_failed
          | :not_saved
          | :cancel
          | :confirm

  @doc "The text for `key`, with `%{name}` placeholders filled from `bindings`."
  @spec t(key, keyword) :: String.t()
  def t(key, bindings \\ []) do
    Gettext.dgettext(backend(), @domain, msgid(key), Map.new(bindings))
  end

  @doc "The text for `key` in the plural form of `count`, which is bound as `%{count}`."
  @spec n(:results | :records, non_neg_integer) :: String.t()
  def n(key, count) do
    {singular, plural} = msgids(key)
    Gettext.dngettext(backend(), @domain, singular, plural, count)
  end

  # what a filter change found, for the live region
  defp msgids(:results), do: dngettext_noop("ash_table", "1 result", "%{count} results")
  # the total of a table that does not know where its page lies in it
  defp msgids(:records), do: dngettext_noop("ash_table", "1 record", "%{count} records")

  @doc """
  A text of the resource's as the table shows it: translated when the
  `ash_table` domain of the host's backend has it as a message, else as it is.
  """
  @spec label(String.t()) :: String.t()
  def label(""), do: ""
  def label(text) when is_binary(text), do: Gettext.dgettext(backend(), @domain, text)

  @doc """
  A message of an action, with its variables: through the host's error
  translator when one is configured, else with the variables filled in.
  """
  @spec error({String.t(), keyword | map}) :: String.t()
  def error({message, vars}) when is_binary(message) do
    vars = vars(vars)

    case Application.get_env(:ash_table, :translate_error) do
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

  defp backend, do: Application.get_env(:ash_table, :gettext_backend, AshTable.Gettext)

  defp msgid(:no_records), do: dgettext_noop("ash_table", "No records")
  defp msgid(:read_failed), do: dgettext_noop("ash_table", "The records could not be loaded.")

  defp msgid(:not_allowed),
    do: dgettext_noop("ash_table", "You are not allowed to see these records.")

  # names the table, so that two tables in a page have two landmarks
  defp msgid(:pagination), do: dgettext_noop("ash_table", "Pagination: %{table}")
  defp msgid(:previous), do: dgettext_noop("ash_table", "Previous")
  defp msgid(:next), do: dgettext_noop("ash_table", "Next")
  defp msgid(:page), do: dgettext_noop("ash_table", "Page %{page}")
  defp msgid(:go_to_page), do: dgettext_noop("ash_table", "Go to page %{page}")
  defp msgid(:range), do: dgettext_noop("ash_table", "%{from}–%{to}")
  defp msgid(:range_of_total), do: dgettext_noop("ash_table", "%{from}–%{to} of %{total}")
  defp msgid(:yes), do: dgettext_noop("ash_table", "Yes")
  defp msgid(:no), do: dgettext_noop("ash_table", "No")
  defp msgid(:not_available), do: dgettext_noop("ash_table", "Not available")
  defp msgid(:operator_contains), do: dgettext_noop("ash_table", "contains")
  defp msgid(:operator_equals), do: dgettext_noop("ash_table", "equals")
  defp msgid(:operator_starts_with), do: dgettext_noop("ash_table", "starts with")
  defp msgid(:operator_is_empty), do: dgettext_noop("ash_table", "is empty")
  defp msgid(:operator_greater_than), do: dgettext_noop("ash_table", "greater than")
  defp msgid(:operator_less_than), do: dgettext_noop("ash_table", "less than")
  defp msgid(:operator_at_least), do: dgettext_noop("ash_table", "at least")
  defp msgid(:operator_at_most), do: dgettext_noop("ash_table", "at most")
  defp msgid(:operator_on), do: dgettext_noop("ash_table", "on")
  defp msgid(:operator_before), do: dgettext_noop("ash_table", "before")
  defp msgid(:operator_after), do: dgettext_noop("ash_table", "after")
  defp msgid(:operator_is), do: dgettext_noop("ash_table", "is")
  defp msgid(:any), do: dgettext_noop("ash_table", "Any")
  defp msgid(:filter), do: dgettext_noop("ash_table", "Filter %{column}")
  defp msgid(:filter_operator), do: dgettext_noop("ash_table", "How to filter %{column}")
  defp msgid(:invalid_filter), do: dgettext_noop("ash_table", "Not a valid value")
  defp msgid(:clear_filter), do: dgettext_noop("ash_table", "Clear the %{column} filter")
  defp msgid(:clear_filters), do: dgettext_noop("ash_table", "Clear filters")
  defp msgid(:results_updated), do: dgettext_noop("ash_table", "Results updated")

  defp msgid(:record_gone),
    do: dgettext_noop("ash_table", "This record is no longer available.")

  defp msgid(:error_on_field), do: dgettext_noop("ash_table", "%{field}: %{message}")

  defp msgid(:edit_not_allowed),
    do: dgettext_noop("ash_table", "You are not allowed to change this.")

  defp msgid(:save_failed), do: dgettext_noop("ash_table", "This could not be saved.")
  defp msgid(:not_saved), do: dgettext_noop("ash_table", "%{column} was not saved: %{message}")
  defp msgid(:cancel), do: dgettext_noop("ash_table", "Cancel")
  defp msgid(:confirm), do: dgettext_noop("ash_table", "Confirm")
end
