defmodule AshTable.Model.Argument do
  @moduledoc false
  # One input of the argument line: an argument that a person gives before
  # the table reads. Either an argument of the read action behind the table,
  # or one of a calculation column that the block asks for (`ask`).
  #
  #   * `name` is the argument's name, and `column` the name of the column
  #     whose calculation it is an argument of; nil for an argument of the
  #     read action. The two together are its `key/1`.
  #   * `label` is what its input is called: what the block says, else the
  #     humanised name. `column_label` is the label of the column of an
  #     asked argument that has no label of its own: the two are shown
  #     together ("Price in: Currency"), so that it is clear which column
  #     the input belongs to.
  #   * `type`, `cell_type`, `values` and `editor` are those of an input of
  #     the action panel (`AshTable.Model.Input`): the control is the one
  #     its type has there, as far as it holds one value or a list of them
  #     (`AshTable.Resource.Arguing`).
  #   * `required?` says whether the argument can be empty (`allow_nil?`).
  #   * `default` is what the argument is while the person has chosen
  #     nothing, and what its input shows then. For an argument of the read
  #     action it is the static default of the action's argument, which Ash
  #     applies itself. For an asked argument it is the default of its `ask`,
  #     else the one the argument has in the resource; where that is
  #     computed, `default_fun` holds the function of the page's assigns, and
  #     `AshTable.Model.defaults/2` puts its value here.
  #   * `time_zone` is the zone of the page, which its input shows a
  #     datetime in (`AshTable.Model.zoned/2`).

  alias AshTable.Format

  @enforce_keys [:name, :label, :cell_type, :editor]
  defstruct [
    :name,
    :column,
    :label,
    :column_label,
    :type,
    :cell_type,
    :values,
    :editor,
    :default,
    :default_fun,
    required?: false,
    time_zone: "Etc/UTC"
  ]

  @typedoc "What a person typed or chose for an argument: text, or for an array the texts of its values."
  @type typed :: String.t() | [String.t()]

  @type key :: {atom | nil, atom}

  @type t :: %__MODULE__{
          name: atom,
          column: atom | nil,
          label: String.t(),
          column_label: String.t() | nil,
          type: {Ash.Type.t(), keyword},
          cell_type: AshTable.Model.CellType.t(),
          values: AshTable.Model.CellType.values() | nil,
          editor: AshTable.Resource.Editing.editor() | :plain,
          default: term,
          default_fun: (map -> term) | nil,
          required?: boolean,
          time_zone: AshTable.Zone.t()
        }

  @doc "What an argument is told apart by: the column it belongs to, nil for the read action's, and its name."
  @spec key(t) :: key
  def key(%__MODULE__{column: column, name: name}), do: {column, name}

  @doc """
  What the argument's input holds while the person has chosen nothing: its
  default, as the control writes it. A box that is not ticked says "false";
  an array is the list of its values.
  """
  @spec rest(t) :: typed
  def rest(%__MODULE__{cell_type: {:array, _item}, default: default} = argument),
    do: Format.input(argument, List.wrap(default), argument.time_zone)

  def rest(%__MODULE__{cell_type: :boolean, default: nil}), do: "false"
  def rest(%__MODULE__{default: nil}), do: ""

  def rest(%__MODULE__{default: default} = argument),
    do: Format.input(argument, default, argument.time_zone) || ""

  @doc """
  What Ash is given for the argument: what the person chose (`chosen`, by
  key), as it was typed, which Ash casts as it casts anything from outside.
  Where they chose nothing:

    * an argument of the read action is not given, and Ash applies its
      default. Only a box says what it shows, as a form does: "false";
    * an asked argument is given its default, the value itself.

  `:none` where nothing is given.
  """
  @spec given(t, %{optional(key) => typed}) :: {:ok, term} | :none
  def given(%__MODULE__{} = argument, chosen) do
    case Map.fetch(chosen, key(argument)) do
      {:ok, typed} -> {:ok, typed}
      :error -> ungiven(argument)
    end
  end

  defp ungiven(%__MODULE__{column: column, default: default})
       when not is_nil(column) and not is_nil(default),
       do: {:ok, default}

  defp ungiven(%__MODULE__{cell_type: :boolean, default: nil}), do: {:ok, "false"}
  defp ungiven(_argument), do: :none
end
