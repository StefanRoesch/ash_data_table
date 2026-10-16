defmodule AshDataTable.Resource.Verifiers.VerifyActions do
  @moduledoc false
  # The `action`s of the block, which are its row actions and its table
  # actions, and its `create_action`.
  use Spark.Dsl.Verifier

  alias AshDataTable.Resource.Acting
  alias AshDataTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)
    tables = AshDataTable.Resource.Info.tables(dsl)

    errors = Enum.flat_map(tables, &errors(dsl, module, &1))

    case {errors, Enum.flat_map(tables, &one_click_deletes(dsl, &1))} do
      {[], []} -> :ok
      {[], warnings} -> {:warn, warnings}
      {errors, _warnings} -> {:error, errors}
    end
  end

  defp errors(dsl, module, table) do
    declared =
      for declaration <- table.actions,
          {:error, reason} <- [usable(dsl, declaration)] do
        DslError.exception(
          module: module,
          path: Table.path(table) ++ [:action, declaration.name],
          message: Acting.message(reason),
          location: Spark.Dsl.Entity.anno(declaration)
        )
      end

    declared ++
      create_errors(dsl, module, table) ++
      row_refresh_errors(dsl, module, table) ++ result_read_errors(dsl, module, table)
  end

  defp create_errors(dsl, module, table) do
    reason =
      case Acting.create_action(dsl, table) do
        {:error, reason} ->
          reason

        {:ok, action} ->
          with [input | _] <- Acting.unusable(dsl, action),
               do: no_field(dsl, :create, action, input)

        :none ->
          []
      end

    case reason do
      [] ->
        []

      reason ->
        [
          DslError.exception(
            module: module,
            path: Table.path(table) ++ [:create_action],
            message: Acting.message(reason),
            location: Table.option_anno(dsl, table, :create_action)
          )
        ]
    end
  end

  # After an action the row is shown from the action's result, with the
  # table's calculations, aggregates and reference columns loaded onto it.
  # Ash loads those through the primary read action.
  defp row_refresh_errors(dsl, module, table) do
    columns =
      for column <- table.columns,
          field =
            Ash.Resource.Info.attribute(module, column.name) ||
              Ash.Resource.Info.calculation(module, column.name) ||
              Ash.Resource.Info.aggregate(module, column.name) ||
              Ash.Resource.Info.relationship(module, column.name),
          do: {field, column}

    case Acting.unloadable_after_action(module, table, columns) do
      [] ->
        []

      loaded ->
        [
          DslError.exception(
            module: module,
            path: Table.path(table),
            message:
              "The table has row actions or a create action and shows calculations, aggregates or reference columns " <>
                "(#{Enum.map_join(loaded, ", ", &"`#{&1}`")}), but the resource has no primary read action. " <>
                "After an action the row is shown with those fields, which Ash loads through the primary read action. " <>
                "Mark a read action `primary? true`.",
            location: Table.anno(dsl, table)
          )
        ]
    end
  end

  # What an action returns is loaded by Ash through the primary read action,
  # which the table then runs with the action. Here, and not with the
  # editing, because it is the same for an edit, a row action and a create.
  defp result_read_errors(dsl, module, table) do
    private =
      case Acting.private_result_read(module, table) do
        nil -> []
        name -> [{:result_read_not_public, name}]
      end

    # and through that action as it is: without arguments
    unanswered =
      case Acting.unanswered_result_read(module, table) do
        nil -> []
        {name, argument} -> [{:result_read_needs_argument, name, argument}]
      end

    for reason <- private ++ unanswered do
      DslError.exception(
        module: module,
        path: Table.path(table),
        message: Acting.message(reason),
        location: Table.anno(dsl, table)
      )
    end
  end

  # A public update or destroy action, or a public generic action, with a
  # field in the action panel for everything it does not run without. The
  # argument that takes a row's primary key is given by the table, and
  # needs none.
  defp usable(dsl, declaration) do
    with {:ok, kind, action} <- Acting.offered(dsl, declaration),
         {:ok, _action} <- bulk(dsl, kind, action, declaration),
         [input | _] <-
           Acting.unusable(
             dsl,
             action,
             declaration.record_argument,
             declaration.references,
             Acting.page_names(declaration)
           ) do
      {:error, no_field(dsl, kind, action, input)}
    end
  end

  # A required input without a field. Where it is an argument that hands
  # keys to a relationship, the reason is that its records cannot be chosen.
  defp no_field(dsl, kind, action, input) do
    case input.kind == :argument && Acting.unchosen(dsl, action, input.name) do
      {relationship, reason} -> {:no_field, kind, action.name, input, relationship, reason}
      _typed -> {:no_field, kind, action.name, input}
    end
  end

  # `bulk?` can only switch off: an action that cannot run on several
  # records at once is not made to by saying so. A table action runs on no
  # record at all.
  defp bulk(_dsl, :table, action, %{bulk?: true}),
    do: {:error, {:table_action_not_bulk, action.name}}

  defp bulk(dsl, :row, action, %{bulk?: true}) do
    case Acting.unrepeatable(dsl, action) do
      [] -> {:ok, action}
      attributes -> {:error, {:not_bulk, action.name, attributes}}
    end
  end

  defp bulk(_dsl, _kind, action, _declaration), do: {:ok, action}

  # A destroy action that runs at one click is a choice the block has to
  # make visibly: with a question, or with `confirm false`.
  defp one_click_deletes(dsl, table) do
    for %{confirm: nil} = declaration <- table.actions,
        match?({:ok, :row, %{type: :destroy}}, Acting.offered(dsl, declaration)) do
      message =
        "The row action `#{declaration.name}` is a destroy action without `confirm`: one click " <>
          "on its button deletes the record, and nothing asks first. Give it a question " <>
          "(`confirm \"Delete this record?\"`), or say that a delete in one click is meant " <>
          "with `confirm false`."

      case Spark.Dsl.Entity.anno(declaration) do
        nil -> message
        location -> {message, location}
      end
    end
  end
end
