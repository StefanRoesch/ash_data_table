defmodule AshTable.Resource.Verifiers.VerifyColumns do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias AshTable.Model.Operator
  alias AshTable.Resource.Arguing
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
    argument_errors(column, field, module) ++
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
  # A table neither sorts nor filters by it: a sort through a relationship
  # is not authorized by Ash (internal ticket #31), and filtering by a
  # related record is not built yet. It is edited as any column is, through
  # an `update_action`: one that accepts the relationship's foreign key,
  # which a person sets by choosing a record of the destination's table.
  defp reference_errors(column, relationship, module) do
    case Referencing.reference(relationship) do
      {:ok, _reference} ->
        argument_errors(column, relationship, module) ++
          reference_option_errors(column, module) ++
          update_action_errors(column, relationship, module) ++
          confirm_errors(column, relationship, module)

      {:error, reason} ->
        [error(column, module, Referencing.message(reason))]
    end
  end

  defp reference_option_errors(column, module) do
    shows = "`#{column.name}` shows the label of a related record"

    for {option, message} <- [
          sortable?:
            "#{shows}, which a table does not sort by, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`.",
          filterable?:
            "#{shows}, which a table does not filter by, so `filterable? true` has no effect. `filterable?` can only switch filtering off; remove it or set it to `false`."
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
              never_edited(module, field, column)
          )
        ]
    end
  end

  defp confirm_errors(_column, _field, _module), do: []

  # A column that names a relationship is edited through an action that
  # takes the related record: as the relationship's foreign key, or through
  # an argument that it hands to the relationship. Which is said in its own
  # words, unless there is nothing to choose a record with: then that is why.
  defp never_edited(module, %Ash.Resource.Relationships.BelongsTo{} = relationship, column) do
    with {:ok, action} <- Editing.behind(module, column),
         {:error, {:no_picker, reason}} <- Editing.written(module, action, relationship) do
      Referencing.no_picker(relationship, reason)
    else
      _no_action_or_not_taken ->
        case Editing.obstacle(module, relationship) do
          nil ->
            "A column that names a relationship is edited through an `update_action`, its own or the table's, that accepts the relationship's foreign key, `#{relationship.source_attribute}`, or has an argument that a `manage_relationship` change hands to the relationship."

          obstacle ->
            Editing.never_edited(obstacle)
        end
    end
  end

  defp never_edited(module, field, _column),
    do: Editing.never_edited(Editing.obstacle(module, field))

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
        # what an edit gives the action, and what the action needs besides
        {taken, given} =
          case Editing.written(module, action, field) do
            {:ok, written} -> {[], Editing.given(written)}
            {:error, reason} -> {[not_written(column, field, action, reason, module)], []}
          end

        taken ++
          for argument <- Editing.required_arguments(action) -- given do
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

  defp read_only(column, {:no_picker, relationship, reason}) do
    "`#{column.name}` is edited by choosing a record of the destination's table, and there is nothing to choose it with, so the column is read-only and its `update_action` has no effect. " <>
      Referencing.no_picker(relationship, reason) <> " Remove `update_action` from this column."
  end

  defp read_only(column, {:no_editor, type}) do
    "`#{column.name}` has the type `#{inspect(type)}`, which a table has no editor for, so the column is read-only and its `update_action` has no effect. A table edits text, numbers, booleans, dates, datetimes and enums, arrays of those, embedded resources and maps whose fields are of those, and unions whose kinds are. Remove `update_action` from this column."
  end

  defp read_only(column, {:sensitive, type}) do
    "`#{column.name}` is declared `sensitive?: true` and has the type `#{inspect(type)}`. A table hides what is typed for a sensitive field, which it can do for text and for a number only, so the column is read-only and its `update_action` has no effect. Remove `update_action` from this column; a row action can still change the value."
  end

  defp read_only(column, {:no_fields, type, obstacle}) do
    "`#{column.name}` has the type `#{inspect(type)}`, which a table edits field by field, and here it cannot, so the column is read-only and its `update_action` has no effect. " <>
      obstacle <> " Remove `update_action` from this column."
  end

  defp read_only(column, {:no_kinds, type, obstacle}) do
    "`#{column.name}` has the type `#{inspect(type)}`, a union, which a table edits kind by kind, and here it cannot, so the column is read-only and its `update_action` has no effect. " <>
      obstacle <> " Remove `update_action` from this column."
  end

  # Why the column's own action cannot save an edit of it.
  defp not_written(
         column,
         %Ash.Resource.Relationships.BelongsTo{} = relationship,
         action,
         reason,
         module
       ) do
    message =
      case reason do
        # the key the action accepts is not one a table sets
        {:no_picker, reason} -> read_only(column, {:no_picker, relationship, reason})
        reason -> Editing.not_written(action.name, relationship, reason)
      end

    option_error(column, module, :update_action, message)
  end

  defp not_written(column, _field, action, _not_accepted, module) do
    option_error(
      column,
      module,
      :update_action,
      "The update action `#{action.name}` does not accept `#{column.name}`, so it cannot save an edit of this column."
    )
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
          path: [:table, :column, column.key, :sortable?],
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
          path: [:table, :column, column.key, :filterable?],
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

  # How the column gives the arguments of its calculation, and that a
  # column of anything else gives none: see `AshTable.Resource.Arguing`.
  defp argument_errors(column, field, module) do
    for {option, reason} <- Arguing.mistakes(module, field, column) do
      message = Arguing.message(reason)

      case option do
        option when option in [:as, :arguments] -> option_error(column, module, option, message)
        :ask -> ask_error(column, module, reason, message)
        nil -> error(column, module, message)
      end
    end
  end

  # At the `ask` the mistake is about, when it is about one.
  defp ask_error(column, module, reason, message) do
    name =
      case reason do
        {:not_a_calculation, _field, :ask} -> nil
        {:no_input, :ask, _calculation, %{name: name}} -> name
        {_what, _calculation, name} -> name
        {_what, _calculation, name, _more} -> name
        {_what, _calculation, name, _value, _where} -> name
      end

    ask = Enum.find(column.asks || [], &(&1.name == name))

    DslError.exception(
      module: module,
      path: [:table, :column, column.key, :ask] ++ List.wrap(name),
      message: message,
      location: (ask && Spark.Dsl.Entity.anno(ask)) || Spark.Dsl.Entity.anno(column)
    )
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
      path: [:table, :column, column.key, option],
      message: message,
      location: Spark.Dsl.Entity.property_anno(column, option)
    )
  end

  defp error(column, module, message) do
    DslError.exception(
      module: module,
      path: [:table, :column, column.key],
      message: message,
      location: Spark.Dsl.Entity.anno(column)
    )
  end
end
