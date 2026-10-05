defmodule AshTable.Model.Pagination do
  @moduledoc """
  How a table pages through its records.

    * `strategy` is `:offset`, `:keyset`, or `:none` for a read action without
      pagination, which loads everything.
    * `page_size` is the read action's `default_limit`, or 25 when it has
      none, and never above the action's `max_page_size`. It is `nil` when the
      strategy is `:none`.
    * `countable?` says whether the action can report the total.
  """

  @enforce_keys [:strategy, :page_size, :countable?]
  defstruct [:strategy, :page_size, :countable?]

  @type t :: %__MODULE__{
          strategy: :offset | :keyset | :none,
          page_size: pos_integer | nil,
          countable?: boolean
        }
end
