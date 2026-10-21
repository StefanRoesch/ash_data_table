defmodule AshDataTable.Test.Submitting do
  @moduledoc """
  The writes of an action panel, below the live layer: what its button runs
  (`AshDataTable.Operation.submit/1`), with what a panel holds of it, for
  the tests of what an action is given and what it says. A row is named
  `"k"`; the veto lets everything through.

  `opts` are who asks (as `AshDataTable.Query.read/3` takes them, with
  `page_values`, which the write is given), and what the panel holds:
  `files` (by argument name), `cleared` (the inputs asked to be emptied)
  and `picked_with` (what the picker's read action was given for a key).
  """

  alias AshDataTable.Operation
  alias AshDataTable.Operation.Input

  @doc "The save of a map cell of `column` (by name) on the record of `pk`."
  def cell(model, column, pk, params, opts \\ []),
    do:
      submit(
        model,
        {:submit_cell, "k", column, held(model, inputs(model, column), params, opts)},
        pk,
        [],
        opts
      )

  @doc "A row action from its panel, on the record of `pk`."
  def row(model, action, pk, params, opts \\ []),
    do:
      submit(
        model,
        {:submit_row, "k", action, held(model, action.inputs, params, opts)},
        pk,
        [],
        opts
      )

  @doc "A table action from its panel."
  def table(model, action, params, opts \\ []),
    do:
      submit(
        model,
        {:submit_table, action, held(model, action.inputs, params, opts)},
        nil,
        [action],
        opts
      )

  @doc "The create action from its panel."
  def create(model, action, params, opts \\ []),
    do:
      submit(
        model,
        {:submit_create, action, held(model, action.inputs, params, opts)},
        nil,
        [],
        opts
      )

  defp inputs(model, name) do
    column = Enum.find(model.columns, &(&1.name == name))
    [AshDataTable.Model.input(model, column)]
  end

  defp held(model, inputs, params, opts) do
    %{
      params: params,
      form: %{id: "panel"},
      inputs: inputs,
      time_zone: model.time_zone,
      cleared: Keyword.get(opts, :cleared, []),
      picked_with: Keyword.get(opts, :picked_with, %{})
    }
  end

  defp submit(model, intent, pk, offered, opts) do
    files = Keyword.get(opts, :files, %{})
    page_values = Keyword.get(opts, :page_values, %Input{}.page_values)

    Operation.submit(%Input{
      intent: intent,
      model: model,
      opts: Keyword.drop(opts, [:files, :cleared, :picked_with, :page_values]),
      rows: if(pk, do: %{"k" => %{pk: pk}}, else: %{}),
      read?: true,
      offered: %{table: offered, bulk: []},
      with_files: fn run -> run.(files) end,
      page_values: page_values
    })
  end
end
