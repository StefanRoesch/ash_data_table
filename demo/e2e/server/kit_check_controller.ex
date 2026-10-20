defmodule DemoWeb.E2E.KitCheckController do
  @moduledoc """
  The browser's kit check (`e2e/kit_check.spec.ts`): what a page drew, as
  the browser shows it (`document.body.outerHTML`), checked by
  `AshDataTable.KitCase.problems/4` for the state and presentation the
  spec drove it into. Answers the list of what the page lacks.
  """
  use DemoWeb, :controller

  alias AshDataTable.KitCase

  @states Map.new(
            KitCase.states() ++ [:filter_panel, :row_selected, :related, :full_view],
            &{Atom.to_string(&1), &1}
          )
  @presentations Map.new(KitCase.presentations(), &{Atom.to_string(&1), &1})

  def check(conn, %{
        "html" => html,
        "state" => state,
        "presentation" => presentation,
        "key" => key
      }) do
    problems =
      KitCase.problems(
        html,
        Map.fetch!(@states, state),
        Map.fetch!(@presentations, presentation),
        key
      )

    json(conn, %{problems: problems})
  end
end
