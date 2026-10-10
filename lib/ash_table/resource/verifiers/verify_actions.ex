defmodule AshTable.Resource.Verifiers.VerifyActions do
  @moduledoc false
  # The row actions of the block, and its `create_action`.
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Acting
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for declaration <- AshTable.Resource.Info.actions(dsl),
          {:error, reason} <- [usable(dsl, declaration)] do
        DslError.exception(
          module: module,
          path: [:table, :action, declaration.name],
          message: Acting.message(reason),
          location: Spark.Dsl.Entity.anno(declaration)
        )
      end

    errors =
      errors ++
        create_errors(dsl, module) ++
        row_refresh_errors(dsl, module) ++ result_read_errors(dsl, module)

    case {errors, one_click_deletes(dsl)} do
      {[], []} -> :ok
      {[], warnings} -> {:warn, warnings}
      {errors, _warnings} -> {:error, errors}
    end
  end

  defp create_errors(dsl, module) do
    reason =
      case Acting.create_action(dsl) do
        {:error, reason} ->
          reason

        {:ok, action} ->
          with [input | _] <- Acting.unusable(dsl, action),
               do: {:no_field, :create, action.name, input}

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
            path: [:table, :create_action],
            message: Acting.message(reason),
            location: Spark.Dsl.Transformer.get_opt_anno(dsl, [:table], :create_action)
          )
        ]
    end
  end

  # After an action the row is shown from the action's result, with the
  # table's calculations, aggregates and reference columns loaded onto it.
  # Ash loads those through the primary read action.
  defp row_refresh_errors(dsl, module) do
    columns =
      for column <- AshTable.Resource.Info.columns(dsl),
          field =
            Ash.Resource.Info.attribute(module, column.name) ||
              Ash.Resource.Info.calculation(module, column.name) ||
              Ash.Resource.Info.aggregate(module, column.name) ||
              Ash.Resource.Info.relationship(module, column.name),
          do: {field, column}

    case Acting.unloadable_after_action(module, columns) do
      [] ->
        []

      loaded ->
        [
          DslError.exception(
            module: module,
            path: [:table],
            message:
              "The table has row actions or a create action and shows calculations, aggregates or reference columns " <>
                "(#{Enum.map_join(loaded, ", ", &"`#{&1}`")}), but the resource has no primary read action. " <>
                "After an action the row is shown with those fields, which Ash loads through the primary read action. " <>
                "Mark a read action `primary? true`.",
            location: Spark.Dsl.Transformer.get_section_anno(dsl, [:table])
          )
        ]
    end
  end

  # What an action returns is loaded by Ash through the primary read action,
  # which the table then runs with the action. Here, and not with the
  # editing, because it is the same for an edit, a row action and a create.
  defp result_read_errors(dsl, module) do
    private =
      case Acting.private_result_read(module) do
        nil -> []
        name -> [{:result_read_not_public, name}]
      end

    # and through that action as it is: without arguments
    unanswered =
      case Acting.unanswered_result_read(module) do
        nil -> []
        {name, argument} -> [{:result_read_needs_argument, name, argument}]
      end

    for reason <- private ++ unanswered do
      DslError.exception(
        module: module,
        path: [:table],
        message: Acting.message(reason),
        location: Spark.Dsl.Transformer.get_section_anno(dsl, [:table])
      )
    end
  end

  # A public update or destroy action, with a field in the action panel for
  # everything it does not run without.
  defp usable(dsl, %{name: name} = declaration) do
    with {:ok, action} <- Acting.row_action(dsl, name),
         {:ok, _action} <- bulk(dsl, action, declaration),
         [input | _] <- Acting.unusable(dsl, action) do
      {:error, {:no_field, :row, name, input}}
    end
  end

  # `bulk?` can only switch off: an action that cannot run on several
  # records at once is not made to by saying so.
  defp bulk(dsl, action, %{bulk?: true}) do
    case Acting.unrepeatable(dsl, action) do
      [] -> {:ok, action}
      attributes -> {:error, {:not_bulk, action.name, attributes}}
    end
  end

  defp bulk(_dsl, action, _declaration), do: {:ok, action}

  # A destroy action that runs at one click is a choice the block has to
  # make visibly: with a question, or with `confirm false`.
  defp one_click_deletes(dsl) do
    for %{confirm: nil} = declaration <- AshTable.Resource.Info.actions(dsl),
        match?({:ok, %{type: :destroy}}, Acting.row_action(dsl, declaration.name)) do
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
