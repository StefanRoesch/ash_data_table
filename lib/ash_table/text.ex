defmodule AshTable.Text do
  @moduledoc false
  # Every string a table shows to a person goes through `t/2`, so that Gettext
  # can be put behind it later without touching the callers.

  @texts %{
    no_records: "No records",
    read_failed: "The records could not be loaded.",
    not_allowed: "You are not allowed to see these records.",
    pagination: "Pagination",
    previous: "Previous",
    next: "Next",
    page: "Page %{page}",
    go_to_page: "Go to page %{page}",
    range: "%{from}–%{to}",
    range_of_total: "%{from}–%{to} of %{total}",
    yes: "Yes",
    no: "No",
    not_available: "Not available",
    operator_contains: "contains",
    operator_equals: "equals",
    operator_starts_with: "starts with",
    operator_is_empty: "is empty",
    operator_greater_than: "greater than",
    operator_less_than: "less than",
    operator_at_least: "at least",
    operator_at_most: "at most",
    operator_on: "on",
    operator_before: "before",
    operator_after: "after",
    operator_is: "is",
    any: "Any",
    filter: "Filter %{column}",
    filter_operator: "How to filter %{column}",
    invalid_filter: "Not a valid value",
    clear_filter: "Clear the %{column} filter",
    clear_filters: "Clear filters",
    one_result: "1 result",
    results: "%{count} results",
    results_updated: "Results updated"
  }

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
          | :one_result
          | :results
          | :results_updated

  @doc "The text for `key`, with `%{name}` placeholders filled from `bindings`."
  @spec t(key, keyword) :: String.t()
  def t(key, bindings \\ []) do
    Enum.reduce(bindings, Map.fetch!(@texts, key), fn {name, value}, text ->
      String.replace(text, "%{#{name}}", to_string(value))
    end)
  end
end
