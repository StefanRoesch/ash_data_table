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
    not_available: "Not available"
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

  @doc "The text for `key`, with `%{name}` placeholders filled from `bindings`."
  @spec t(key, keyword) :: String.t()
  def t(key, bindings \\ []) do
    Enum.reduce(bindings, Map.fetch!(@texts, key), fn {name, value}, text ->
      String.replace(text, "%{#{name}}", to_string(value))
    end)
  end
end
