defmodule AshDataTable.Geometry do
  @moduledoc """
  Where a table's columns and rows stand in its grid: one value per
  table, made by the table as its model or what it selects changes, and
  given to the parts that place cells and rows (`grid`, `row`, `footer`,
  `full_view` of `AshDataTable.Kit`).

  Its fields are the kit contract; its functions are the table's own.

    * `lead` - the columns before the first data column: the box that
      selects a row, where rows are selected, and after it the expander,
      where rows expand (0, 1 or 2). The expander, where there is one,
      stands at `lead`, the box at 1
    * `trail` - the columns after the last data column: 1 where the rows
      have an actions cell (row actions, or the page's "Open"), else 0.
      The actions cell, where there is one, stands at `colcount`
    * `columns` - the data columns, `length(model.columns)`; the data
      column at `index` (from 0, in the model's order) stands at
      `lead + index + 1`
    * `colcount` - every column of the grid (`aria-colcount`): `lead`,
      `columns` and `trail`; what a cell that spans the grid spans
    * `header_rows` - the rows above the records: the header row, and the
      filter row where a column filters (1 or 2)
    * `summary?` - whether the grid has a footer row of summaries, the last
      row of all

  The hooks read `lead` from the grid's `data-lead` and the first record's
  row index from the table's `data-first-row`; `assets/js/geometry.js`
  counts with them as this module does, function by function.
  """

  alias AshDataTable.Model

  defstruct lead: 0, trail: 0, columns: 0, colcount: 0, header_rows: 1, summary?: false

  @type t :: %__MODULE__{
          lead: 0..2,
          trail: 0 | 1,
          columns: non_neg_integer,
          colcount: non_neg_integer,
          header_rows: 1 | 2,
          summary?: boolean
        }

  @doc false
  # The geometry of a table drawn from `model` (the person's), whose rows
  # are selected as `selecting` says (nil for not at all), expand where
  # `expandable?`, and offer the page's "Open" where `open_label` is one.
  # The actions cell is there for the row actions or for "Open".
  @spec of(Model.t(), :single | :multi | nil, boolean, String.t() | nil) :: t
  def of(model, selecting, expandable?, open_label) do
    lead = if(selecting, do: 1, else: 0) + if(expandable?, do: 1, else: 0)
    trail = if model.actions != [] or not is_nil(open_label), do: 1, else: 0
    columns = length(model.columns)

    %__MODULE__{
      lead: lead,
      trail: trail,
      columns: columns,
      colcount: lead + columns + trail,
      # a column that filters gives the grid its filter row
      header_rows: if(Enum.any?(model.columns, &(&1.operators != [])), do: 2, else: 1),
      summary?: Model.summarised(model) != []
    }
  end

  @doc false
  # 1-based position of the data column at `index` (from 0) among all
  # columns of the grid (`aria-colindex`).
  @spec colindex(t, non_neg_integer) :: pos_integer
  def colindex(%__MODULE__{lead: lead}, index), do: lead + index + 1

  @doc false
  # The row index (`aria-rowindex`, the header rows counted) of the first
  # record of `page`. Under offset pagination the rows run through all
  # pages; a keyset page does not know how many records lie before it, and
  # counts from its own top. The hook numbers the rows from it, in the
  # order they stand in, after a row was added or taken out.
  @spec first_row(t, map | nil) :: pos_integer
  def first_row(%__MODULE__{header_rows: header_rows}, %{offset: offset})
      when is_integer(offset),
      do: offset + header_rows + 1

  def first_row(%__MODULE__{header_rows: header_rows}, _page), do: header_rows + 1

  @doc false
  # The row index of the record at `n` (from 0) of `page`.
  @spec rowindex(t, map | nil, non_neg_integer) :: pos_integer
  def rowindex(geometry, page, n), do: first_row(geometry, page) + n

  @doc false
  # The rows of the grid in all pages (`aria-rowcount`): the header rows,
  # the records, and the footer row of the summaries where there is one.
  # Where the number of records is not known, -1, which ARIA reads as
  # "unknown".
  @spec rowcount(t, map | nil) :: integer
  def rowcount(%__MODULE__{} = geometry, %{total: total}) when is_integer(total),
    do: total + geometry.header_rows + if(geometry.summary?, do: 1, else: 0)

  def rowcount(_geometry, _page), do: -1

  @doc false
  # The row index of the footer row of the summaries: the last row of all,
  # after the records of every page. Nil where their number is not known.
  @spec summary_row(t, map | nil) :: pos_integer | nil
  def summary_row(%__MODULE__{header_rows: header_rows}, %{total: total})
      when is_integer(total),
      do: total + header_rows + 1

  def summary_row(_geometry, _page), do: nil
end
