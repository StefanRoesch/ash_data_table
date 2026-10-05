defmodule AshTable.Resource.Verifiers.VerifyReadAction do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Reading
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    with {:ok, action} <- Reading.read_action(module),
         {:ok, _strategy} <- Reading.strategy(module, action) do
      :ok
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
        {:error, error(dsl, module, :read_action, read_action_message(reason))}
    end
  end

  defp read_action_message({:not_found, name}),
    do: "The resource has no action named `#{name}`."

  defp read_action_message({:not_a_read_action, name, type}),
    do: "`#{name}` is #{kind(type)} action, not a read action."

  defp read_action_message({:not_public, name}),
    do: "The read action `#{name}` is not public. Only `public?` actions can be behind a table."

  defp read_action_message(:no_primary_read_action),
    do:
      "The resource has no primary read action. Name the read action behind the table with `read_action`."

  defp supported(action) do
    case Reading.supported_strategies(action.pagination) do
      [] -> "It has no pagination."
      strategies -> "It supports: #{Enum.join(strategies, ", ")}."
    end
  end

  defp kind(:action), do: "a generic"
  defp kind(:update), do: "an update"
  defp kind(type), do: "a #{type}"

  defp error(dsl, module, option, message) do
    DslError.exception(
      module: module,
      path: [:table, option],
      message: message,
      location: Spark.Dsl.Transformer.get_opt_anno(dsl, [:table], option)
    )
  end
end
