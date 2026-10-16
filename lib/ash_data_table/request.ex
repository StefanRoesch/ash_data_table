defmodule AshDataTable.Request do
  @moduledoc """
  What the page's `before_action` is told before a table writes: which
  table asks to run which action, from where, on which row or selection.

      def before_action(%AshDataTable.Request{action: :destroy}, _assigns),
        do: {:halt, "Nothing is deleted today."}

      def before_action(_request, _assigns), do: :cont

  It is asked after the table's own checks of what the browser named and
  before the record is read again and the action runs, in the LiveView's
  process. It holds no typed value, no input and no record: the veto can
  only halt (`{:halt, message}`, the message said where the write is), and
  what a page adds to an action goes through `context`,
  `private_arguments` and `page_arguments`, which Ash checks as it checks
  anything else. "Show" and opening a panel are reads, and are not asked.

    * `table` - the id of the table that writes, and `path` the ids from
      the table on the page down to it (a nested table's or a picker's);
    * `resource` and `action` - the action's resource and name;
    * `type` - `:update`, `:create`, `:destroy` or `:action` (a generic
      action);
    * `from` - what asks: `:cell` (a cell saved), `:clear` (a sensitive
      cell emptied), `:reference` (a record chosen for a reference cell),
      `:map_cell` (a map cell's panel), `:row` (a row action), `:table` (a
      table action), `:create` or `:bulk` (an action on a selection);
    * `column` - the column, for a cell; else nil;
    * `key` - the primary key of the row, as a map; nil for a table
      action, a create and a selection;
    * `selection` - for an action on a selection: `:all` (everything the
      filters match) or the rows as the browser named them. The key and
      the selection are claims: the table reads each record again, as the
      person, before it is written.
  """

  @enforce_keys [:resource, :action, :type, :from]
  defstruct table: nil,
            path: [],
            resource: nil,
            action: nil,
            type: nil,
            from: nil,
            column: nil,
            key: nil,
            selection: nil

  @type t :: %__MODULE__{
          table: String.t() | nil,
          path: [String.t()],
          resource: Ash.Resource.t(),
          action: atom,
          type: :update | :create | :destroy | :action,
          from: :cell | :clear | :reference | :map_cell | :row | :table | :create | :bulk,
          column: atom | nil,
          key: map | nil,
          selection: :all | [term] | nil
        }
end
