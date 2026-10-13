defmodule AshTable.Resource.Verifiers.VerifyReadAction do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Arguing
  alias AshTable.Resource.Reading
  alias AshTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    # every table of the resource reads through an action of its own
    errors =
      for table <- AshTable.Resource.Info.tables(dsl),
          error <- errors(dsl, module, table),
          do: error

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp errors(dsl, module, table) do
    with {:ok, action} <- Reading.read_action(module, table),
         {:ok, _strategy} <- Reading.strategy(table, action) do
      argument_errors(dsl, module, table, action)
    else
      {:error, {:unsupported, strategy}} ->
        {:ok, action} = Reading.read_action(module, table)

        [
          error(
            dsl,
            module,
            table,
            :paginate_with,
            "The read action `#{action.name}` does not support #{strategy} pagination. #{supported(action)}"
          )
        ]

      {:error, reason} ->
        [error(dsl, module, table, :read_action, Reading.message(reason))]
    end
  end

  # The arguments of the read action are the person's to give, in the
  # argument line: one the action does not run without has to have an input
  # there, and an `argument` of the block names one of them.
  defp argument_errors(dsl, module, table, action) do
    unanswerable =
      for input <- Arguing.unanswerable(action) do
        error(
          dsl,
          module,
          table,
          :read_action,
          Arguing.message({:no_input, :read, action.name, input})
        )
      end

    declared =
      for {declaration, reason} <- Arguing.declared_mistakes(action, table.arguments) do
        DslError.exception(
          module: module,
          path: Table.path(table) ++ [:argument, declaration.name],
          message: Arguing.message(reason),
          location: Spark.Dsl.Entity.anno(declaration)
        )
      end

    unanswerable ++ declared
  end

  defp supported(action) do
    case Reading.supported_strategies(action.pagination) do
      [] -> "It has no pagination."
      strategies -> "It supports: #{Enum.join(strategies, ", ")}."
    end
  end

  # At the option where the block gives it, else at the table: a table
  # that names no read action is read through the primary one.
  defp error(dsl, module, table, option, message) do
    DslError.exception(
      module: module,
      path: Table.path(table) ++ [option],
      message: message,
      location: Table.option_anno(dsl, table, option) || Table.anno(dsl, table)
    )
  end
end
