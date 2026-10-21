defmodule AshDataTable.Resource.Action do
  @moduledoc """
  An `action` declared in a resource's `table` block: a row action, a
  table action, or an action on the selection.

  This is the declaration as written, as `AshDataTable.Resource.Info.actions/1`
  returns it: an option that was not given is `nil`. The defaults are filled
  in when the table is rendered.

  `references` holds the `reference`s of the action
  (`AshDataTable.Resource.Reference`), in the declared order, and
  `page_arguments` its `page_argument`s (`AshDataTable.Resource.PageArgument`).
  """

  defstruct [
    :name,
    :label,
    :confirm,
    :bulk?,
    :record_argument,
    :selection_argument,
    :sort_argument,
    :__identifier__,
    :__spark_metadata__,
    references: [],
    page_arguments: []
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          confirm: String.t() | false | nil,
          bulk?: boolean | nil,
          record_argument: atom | nil,
          selection_argument: atom | nil,
          sort_argument: atom | nil,
          references: [AshDataTable.Resource.Reference.t()],
          page_arguments: [AshDataTable.Resource.PageArgument.t()]
        }

  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "The action a person runs: a public update or destroy action of the resource, which runs on the record of a row, or a public generic action, which runs on the table as a whole (with `record_argument` on a row, with `selection_argument` once on the selected rows)."
    ],
    label: [
      type: :string,
      doc: "What the action's button says. Defaults to the humanised action name."
    ],
    confirm: [
      type: {:or, [{:literal, false}, :string]},
      doc:
        "A question asked before the action runs. `false` says that the action runs without one on purpose, which silences the warning the compiler gives about a destroy action without `confirm`."
    ],
    bulk?: [
      type: :boolean,
      doc:
        "Whether the action is also offered for the rows a person has selected, to run on all of them at once. Defaults to `true` for every action that can: one that accepts no attribute of which two records cannot hold the same value. `false` leaves it an action of one row; it can only switch off. A generic action without `record_argument` runs on no row, and has nothing to switch off; one with `selection_argument` runs on the selection only."
    ],
    record_argument: [
      type: :atom,
      doc:
        "For a generic action: the argument that is given the primary key of a row. The action is then a row action: its button stands in every row, the argument is filled in by the table and not asked for, and the action's other arguments are asked for in the action panel. The argument has to be public and of the type of the resource's primary key, which has to be one attribute."
    ],
    selection_argument: [
      type: :atom,
      doc:
        "For a generic action: the argument that is given the primary keys of the selected rows, all of them at once. The action is then an action on the selection: its button stands in the line above the grid while rows are selected, and it runs once, given every selected key that the person may read (\"all that match\" read then, through the table's read action and with its filters). The argument is filled in by the table and not asked for. It has to be public and a list of the type of the resource's primary key, which has to be one attribute."
    ],
    sort_argument: [
      type: :atom,
      doc:
        "With `selection_argument`: the argument that is given the table's sort as the person has chosen it, in the syntax of `Ash.Query.sort_input/2` (`\"title\"`, `\"-due_on\"`), or nil where they have chosen none, or sort by a column of a calculation with arguments, which that syntax cannot say. A read the action runs over the keys can then keep the table's order. It has to be a public argument of the type `:string`."
    ]
  ]

  @doc false
  def schema, do: @schema
end
