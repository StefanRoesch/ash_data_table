defmodule AshTable.Resource.Verifiers.VerifyColumns do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias AshTable.Model.Operator
  alias AshTable.Resource.Editing
  alias AshTable.Resource.Reading
  alias AshTable.Resource.Referencing
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      dsl
      |> AshTable.Resource.Info.columns()
      |> Enum.flat_map(&column_errors(&1, dsl, module))

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp column_errors(column, dsl, module) do
    case field(dsl, column.name) do
      nil ->
        [
          error(
            column,
            module,
            "The resource has no attribute, calculation, aggregate or belongs-to relationship named `#{column.name}`."
          )
        ]

      %{public?: false} ->
        [
          error(
            column,
            module,
            "`#{column.name}` is not public. Only `public?` fields can be columns of a table."
          )
        ]

      field ->
        if Referencing.relationship?(field),
          do: reference_errors(column, field, module),
          else: field_errors(column, field, module)
    end
  end

  defp field_errors(column, field, module) do
    required_argument_errors(column, field, module) ++
      private_read_errors(column, field, module) ++
      sortable_errors(column, module) ++
      filterable_errors(column, field, module) ++
      update_action_errors(column, field, module) ++
      confirm_errors(column, field, module)
  end

  # A column that names a relationship is a reference cell, which shows the
  # related record's label. The destination is looked at, which a verifier
  # may do (see `VerifyRelationships`).
  #
  # The cell is read-only, and a table neither sorts nor filters by it: a
  # sort through a relationship is not authorized by Ash (internal ticket
  # #31), and filtering by a related record is not built yet.
  defp reference_errors(column, relationship, module) do
    case Referencing.reference(relationship) do
      {:ok, _reference} -> reference_option_errors(column, module)
      {:error, reason} -> [error(column, module, Referencing.message(reason))]
    end
  end

  defp reference_option_errors(column, module) do
    shows = "`#{column.name}` shows the label of a related record"

    for {option, message} <- [
          sortable?:
            "#{shows}, which a table does not sort by, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`.",
          filterable?:
            "#{shows}, which a table does not filter by, so `filterable? true` has no effect. `filterable?` can only switch filtering off; remove it or set it to `false`.",
          update_action:
            "#{shows}. Only an attribute can be edited, so a column that names a relationship cannot have an `update_action`.",
          confirm:
            "`#{column.name}` can never be edited, so `confirm` has no effect. It shows the label of a related record."
        ],
        Map.fetch!(column, option) not in [nil, false] do
      option_error(column, module, option, message)
    end
  end

  defp confirm_errors(%{confirm: confirm} = column, field, module) when is_binary(confirm) do
    case Editing.update_action(module, field, column) do
      {:ok, _action} ->
        []

      :none ->
        [
          option_error(
            column,
            module,
            :confirm,
            "`#{column.name}` can never be edited, so `confirm` has no effect. " <>
              Editing.never_edited(Editing.obstacle(module, field))
          )
        ]
    end
  end

  defp confirm_errors(_column, _field, _module), do: []

  # A column's own update action has to be able to save an edit of it. The
  # table-level action is not held to that: what it cannot save is read-only.
  defp update_action_errors(%{update_action: name}, _field, _module) when name in [nil, false],
    do: []

  defp update_action_errors(column, %Ash.Resource.Calculation{}, module) do
    [
      option_error(
        column,
        module,
        :update_action,
        "`#{column.name}` is a calculation. Only an attribute can be edited, so a calculation column cannot have an `update_action`."
      )
    ]
  end

  defp update_action_errors(column, %Ash.Resource.Aggregate{}, module) do
    [
      option_error(
        column,
        module,
        :update_action,
        "`#{column.name}` is an aggregate. Only an attribute can be edited, so an aggregate column cannot have an `update_action`."
      )
    ]
  end

  defp update_action_errors(%{update_action: name} = column, field, module) do
    action = Editing.action(module, name)

    named =
      case action do
        {:error, reason} ->
          [option_error(column, module, :update_action, Editing.message(reason))]

        {:ok, _action} ->
          []
      end

    # What no action can do for the column is reported once, in place of what
    # this one would have to do besides.
    case {Editing.obstacle(module, field), action} do
      {nil, {:ok, action}} ->
        accept_errors(column, field, action, module) ++
          for argument <- Editing.required_arguments(action) do
            option_error(
              column,
              module,
              :update_action,
              "The update action `#{name}` requires the argument `#{argument}`. An inline edit supplies only the cell's value, so the action behind a column must not need anything else."
            )
          end

      {nil, _error} ->
        named

      {obstacle, _action} ->
        named ++ [option_error(column, module, :update_action, read_only(column, obstacle))]
    end
  end

  # A column's own `update_action` on a column that is read-only whatever
  # the action. The calculation and the aggregate have clauses of their own
  # above.
  defp read_only(column, :not_writable) do
    "`#{column.name}` is declared `writable?: false`, so no action can save an edit of it: the column is read-only and its `update_action` has no effect. Remove `update_action` from this column, or make the attribute writable."
  end

  defp read_only(column, {:no_editor, type}) do
    "`#{column.name}` has the type `#{inspect(type)}`, which a table has no editor for, so the column is read-only and its `update_action` has no effect. A table edits text, numbers, booleans, dates, datetimes and enums. Remove `update_action` from this column."
  end

  defp accept_errors(column, field, action, module) do
    if Editing.accepts?(action, field) do
      []
    else
      [
        option_error(
          column,
          module,
          :update_action,
          "The update action `#{action.name}` does not accept `#{column.name}`, so it cannot save an edit of this column."
        )
      ]
    end
  end

  # A mistake in `read_action` or `paginate_with` is reported by
  # `VerifyReadAction`; without a valid one there is nothing to check here.
  defp sortable_errors(%{sortable?: true} = column, module) do
    with {:ok, action} <- Reading.read_action(module),
         {:ok, strategy} <- Reading.strategy(module, action),
         false <- Reading.sortable?(module, column.name, strategy) do
      [
        DslError.exception(
          module: module,
          path: [:table, :column, column.name, :sortable?],
          message:
            "`#{column.name}` cannot be sorted#{strategy_note(strategy)}, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`.",
          location: Spark.Dsl.Entity.property_anno(column, :sortable?)
        )
      ]
    else
      _ -> []
    end
  end

  defp sortable_errors(_column, _module), do: []

  defp filterable_errors(%{filterable?: true} = column, field, module) do
    if Operator.available(module, field) == [] do
      [
        DslError.exception(
          module: module,
          path: [:table, :column, column.name, :filterable?],
          message:
            "`#{column.name}` cannot be filtered, so `filterable? true` has no effect. `filterable?` can only switch filtering off; remove it or set it to `false`.",
          location: Spark.Dsl.Entity.property_anno(column, :filterable?)
        )
      ]
    else
      []
    end
  end

  defp filterable_errors(_column, _field, _module), do: []

  defp strategy_note(:keyset), do: " with keyset pagination"
  defp strategy_note(_strategy), do: ""

  defp required_argument_errors(column, field, module) do
    for name <- Reading.required_arguments(field) do
      error(
        column,
        module,
        "The calculation `#{column.name}` requires the argument `#{name}`. A table cannot supply arguments, so a column can only show a calculation whose arguments are optional or have defaults."
      )
    end
  end

  # An aggregate is read through actions of the related resources, which
  # nothing in the block names, and so is one that a calculation holds.
  # Those resources are looked at, which a verifier may do (see
  # `VerifyRelationships`).
  defp private_read_errors(column, field, module) do
    case Reading.private_read(module, field) do
      nil -> []
      reason -> [error(column, module, Reading.message(reason))]
    end
  end

  defp field(dsl, name) do
    Ash.Resource.Info.attribute(dsl, name) ||
      Ash.Resource.Info.calculation(dsl, name) ||
      Ash.Resource.Info.aggregate(dsl, name) ||
      Ash.Resource.Info.relationship(dsl, name)
  end

  defp option_error(column, module, option, message) do
    DslError.exception(
      module: module,
      path: [:table, :column, column.name, option],
      message: message,
      location: Spark.Dsl.Entity.property_anno(column, option)
    )
  end

  defp error(column, module, message) do
    DslError.exception(
      module: module,
      path: [:table, :column, column.name],
      message: message,
      location: Spark.Dsl.Entity.anno(column)
    )
  end
end
