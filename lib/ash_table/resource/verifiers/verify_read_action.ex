defmodule AshTable.Resource.Verifiers.VerifyReadAction do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Arguing
  alias AshTable.Resource.Reading
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    with {:ok, action} <- Reading.read_action(module),
         {:ok, _strategy} <- Reading.strategy(module, action) do
      case argument_errors(dsl, module, action) do
        [] -> :ok
        errors -> {:error, errors}
      end
    else
      {:error, {:unsupported, strategy}} ->
        {:ok, action} = Reading.read_action(module)

        {:error,
         error(
           dsl,
           module,
           :paginate_with,
           "The read action `#{action.name}` does not support #{strategy} pagination. #{supported(action)}"
         )}

      {:error, reason} ->
        {:error, error(dsl, module, :read_action, Reading.message(reason))}
    end
  end

  # The arguments of the read action are the person's to give, in the
  # argument line: one the action does not run without has to have an input
  # there, and an `argument` of the block names one of them.
  defp argument_errors(dsl, module, action) do
    unanswerable =
      for input <- Arguing.unanswerable(action) do
        error(dsl, module, :read_action, Arguing.message({:no_input, :read, action.name, input}))
      end

    declared =
      for {declaration, reason} <-
            Arguing.declared_mistakes(action, AshTable.Resource.Info.arguments(dsl)) do
        DslError.exception(
          module: module,
          path: [:table, :argument, declaration.name],
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

  defp error(dsl, module, option, message) do
    DslError.exception(
      module: module,
      path: [:table, option],
      message: message,
      location: Spark.Dsl.Transformer.get_opt_anno(dsl, [:table], option)
    )
  end
end
