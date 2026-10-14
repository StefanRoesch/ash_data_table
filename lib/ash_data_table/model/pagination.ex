defmodule AshDataTable.Model.Pagination do
  @moduledoc false
  # How a table pages through its records.
  #
  #   * `strategy` is `:offset`, `:keyset`, or `:none` for a read action without
  #     pagination, which loads everything.
  #   * `page_size` is the read action's `default_limit`, or 25 when it has
  #     none, and never above the action's `max_page_size`. It is `nil` when the
  #     strategy is `:none`.
  #     With `page_sizes` it is the size the table opens with: the action's
  #     `default_limit`, or the first of the sizes as the block wrote them
  #     when the action has none.
  #   * `page_sizes` are the sizes a person can choose between, ascending:
  #     the `page_sizes` of the table's block, every one of them allowed by
  #     the action that is read through, and `page_size` among them. Empty
  #     when the block has none, when there are no pages, and when the action
  #     that is read through does not allow what the block offers.
  #   * `countable?` says whether the action can report the total.

  @enforce_keys [:strategy, :page_size, :countable?]
  defstruct [:strategy, :page_size, :countable?, page_sizes: []]

  @type t :: %__MODULE__{
          strategy: :offset | :keyset | :none,
          page_size: pos_integer | nil,
          page_sizes: [pos_integer],
          countable?: boolean
        }

  @doc """
  How many records a page holds when a person asks for `chosen` of them
  (`AshDataTable.State`'s `per`): that many when it is one of `page_sizes`,
  else `page_size`. What a person asks for is a claim: nothing but a size
  the table offers is ever read with.
  """
  @spec size(t, term) :: pos_integer | nil
  def size(%__MODULE__{page_size: page_size, page_sizes: page_sizes}, chosen) do
    if is_integer(chosen) and chosen in page_sizes, do: chosen, else: page_size
  end
end
