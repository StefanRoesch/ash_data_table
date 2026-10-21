defmodule AshDataTable.Kit.Projection do
  @moduledoc """
  What a part of a table is given to draw (ADR 0004): one finished,
  plain-data projection per part, made by the table and the same for
  every kit, so that a kit only draws. A projection holds values (looked
  up already), texts and the messages they are made of, bundles (the
  attribute maps of `AshDataTable.Attrs`, string keys, which a kit spreads
  on an element), the facts derived from them, and the projections of the
  parts drawn inside it. It never holds a record, a form, an
  `AshDataTable.Model`, an `AshDataTable.State` or a struct of
  `AshDataTable.Present`; it goes to JSON as it is.

  Wherever a projection shows words it has `texts` (by name, the finished
  strings in the person's language) and `messages` (the same names, each
  the message `%{key:, values:}` of `AshDataTable.Messages` it was made
  of; a name may hold a list, and nil where nothing is shown there), or
  `text` and `message` alone in a projection of one text.

  Built so far (stage 9f is under way): `:status`, `:message`, `:confirm`,
  `:pagination`, `:picker`, `:related`, `:full_view`, `:selection_line`,
  `:heading`. The shapes are listed here as each part is moved onto its
  projection.
  """

  alias AshDataTable.Kit.Projection

  @parts %{
    status: Projection.Status,
    message: Projection.Message,
    confirm: Projection.Confirm,
    pagination: Projection.Pagination,
    picker: Projection.Picker,
    related: Projection.Related,
    full_view: Projection.FullView,
    selection_line: Projection.SelectionLine,
    heading: Projection.Heading
  }

  @doc false
  # The projection of `part`, made of `inputs`: the entry fields that part
  # depends on, given one by one by the drawing. `:message` gives a list,
  # one per message the table says now.
  def of(part, inputs), do: Map.fetch!(@parts, part).of(inputs)
end
