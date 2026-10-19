defmodule DemoWeb.E2E.IdsLive do
  @moduledoc """
  A page for the browser test of the ids in the browser (`e2e/contract.spec.ts`):
  every function of `AshDataTable.Ids`, called with sample values, and
  what it made, as JSON (`ids`); and the names of all of its functions
  (`functions`), so that the test finds one without a sample.
  `assets/js/ids.js` must make the same ids. Compiled and routed in the e2e
  environment only.
  """
  use DemoWeb, :live_view

  alias AshDataTable.Ids

  @samples [
    {:row, ["tasks", "42"]},
    {:row, ["tasks-row-1-t-comments", "c-9"]},
    {:cell, ["tasks-row-42", "title"]},
    {:actions_cell, ["tasks-row-42"]},
    {:selector, ["tasks-row-42"]},
    {:expander, ["tasks-row-42"]},
    {:detail, ["tasks-row-42"]},
    {:line_cell, ["tasks-row-42", "comments"]},
    {:line_button, ["tasks-row-42", "comments"]},
    {:line_heading, ["tasks-row-42", "comments"]},
    {:nested_row, ["tasks-row-42", "comments"]},
    {:nested_cell, ["tasks-row-42", "comments"]},
    {:nested_table, ["tasks-row-42", "comments"]},
    {:error, ["tasks-row-42-c-title"]},
    {:head, ["tasks"]},
    {:head_row, ["tasks"]},
    {:header_cell, ["tasks", "title"]},
    {:filter_row, ["tasks"]},
    {:filters, ["tasks"]},
    {:editor, ["tasks", "title"]},
    {:dialog, ["tasks"]},
    {:field, ["tasks", ["place"]]},
    {:field, ["tasks", ["stops", "0", "city"]]},
    {:clear, ["tasks-panel-f-pin"]},
    {:choose, ["tasks-panel-f-owner"]},
    {:unpick, ["tasks-panel-f-helpers", 2]},
    {:argument, ["tasks", "since"]},
    {:argument_value, ["tasks-arg-tags", 0]},
    {:argument_value, ["tasks-arg-tags", "add"]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    ids =
      for {function, args} <- @samples do
        # `:add` is an atom on the server, the text "add" in the browser
        called = Enum.map(args, &if(&1 == "add", do: :add, else: &1))
        %{function: function, args: args, id: apply(Ids, function, called)}
      end

    functions =
      for {name, _arity} <- Ids.module_info(:exports),
          not String.starts_with?(Atom.to_string(name), "_"),
          name != :module_info,
          do: name

    {:ok,
     assign(socket,
       page_title: "Ids",
       ids: Jason.encode!(ids),
       functions: Jason.encode!(Enum.uniq(functions))
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Ids</h1>
      <script id="ids" type="application/json">
        <%= Phoenix.HTML.raw(@ids) %>
      </script>
      <script id="functions" type="application/json">
        <%= Phoenix.HTML.raw(@functions) %>
      </script>
    </Layouts.app>
    """
  end
end
