defmodule AshDataTable.StepTest do
  @moduledoc """
  The step of the live core over the table (`AshDataTable.Live.Core.step/3`,
  stage 9g): an intent gives the table as it is then, the effects the
  adapter applies to the socket (`{:push, …}`, `{:tell, …}`, `{:patch, …}`,
  `{:stream, …}`, `{:async, …}`, `{:uploads, …}`) and the reply to the hook,
  with no socket and no LiveView. One `describe` per topic: what is
  selected, reading (sort, filters, page size, a task's answer, the host's
  refresh), the URL and the argument line, nested tables, cells, the
  picker, the panel (and its submit in two intents, split at the files),
  actions on the selection, live updates, what a table is told, and the
  core's own (`:tidy`, an event of the browser, a host's answer).

  The table is made by hand (`AshDataTable.Table.put/2`), its model built
  for the resource as for everybody (`AshDataTable.Model.build/2`). A table
  that has read before (`read: :before`) reads again beside the process:
  the read is an effect, and no query runs in the step.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Model
  alias AshDataTable.Query
  alias AshDataTable.State
  alias AshDataTable.Table
  alias AshDataTable.Test.Arguing.Price
  alias AshDataTable.Test.Files
  alias AshDataTable.Test.Resource

  # A resource with an action on the selection: run once, given the keys
  # of every selected row.
  defmodule Exports do
    @moduledoc false
    use Ash.Resource,
      domain: AshDataTable.Test.Domain,
      extensions: [AshDataTable.Resource]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
    end

    actions do
      defaults [:read]

      action :export, :integer do
        argument :ids, {:array, :uuid}, allow_nil?: false
        run fn input, _context -> {:ok, length(input.arguments.ids)} end
      end
    end

    table do
      action :export do
        selection_argument :ids
      end
    end
  end

  @context %{assigns: %{}, uploads: %{}, connected?: false, endpoint: nil}

  # the table on the page, "t", of `resource`, its state the default, with
  # a stream, and read before
  defp table(resource \\ Resource, fields \\ []) do
    model = Model.build(resource)

    Table.new()
    |> Table.put(id: "t", path: ["t"], resource: resource, model: model, state: %State{})
    |> Table.put(stream: "t:rows", read: :before)
    |> Table.put(fields)
  end

  # the same, on a page that asked to be told every event (`notify: true`)
  defp told, do: table(Resource, notify: true)

  defp step(table, intent, context \\ @context), do: Core.step(table, intent, context)

  # the read beside the process, as the step asks for it
  defp read?(effects),
    do: Enum.any?(effects, &match?({:async, {:ash_data_table, "t", {:read, _token}}, _fun}, &1))

  describe "what is selected (Selection)" do
    test "the rows the hook names are selected, and the host is told it changed" do
      key = Ash.UUID.generate()
      {table, effects, nil} = step(told(), {:select, {:rows, [key, key]}})

      assert %{selected: [^key], all?: false} = table.entry.selection
      # the hook said it: it is not told back
      assert [{:tell, "t", {:selection_changed, %{selected: [_], all?: false, table: "t"}}}] =
               effects

      # the same selection again tells nothing
      assert {_table, [], nil} = step(table, {:select, {:rows, [key]}})
    end

    test "every record that matches" do
      {table, effects, nil} = step(told(), {:select, :all})

      assert %{selected: [], all?: true} = table.entry.selection
      assert [{:tell, "t", {:selection_changed, %{all?: true}}}] = effects
    end

    test "a picker's table tells the host nothing" do
      assert {_table, [], nil} =
               step(table(Resource, choose: :one, notify: true), {:select, {:rows, ["k"]}})
    end

    test "the host's clear: the hook is told, and the host" do
      {table, _effects, nil} = step(told(), {:select, {:rows, ["k"]}})
      {table, effects, nil} = step(table, :clear_selection)

      assert table.entry.selection.selected == []

      assert [
               {:push, "ash_data_table:select", %{table: "t", all: false, rows: []}},
               {:tell, _, _}
             ] =
               effects
    end

    test "a selection made under other filters is given up after the callback (:tidy)" do
      {table, _effects, nil} = step(told(), {:select, {:rows, ["k"]}})
      {table, [], nil} = step(table, :tidy)
      table = Table.put(table, state: %State{filters: %{name: {:eq, "x"}}})

      assert {table, [{:push, "ash_data_table:select", %{table: "t", rows: []}}, {:tell, _, _}],
              nil} = step(table, :tidy)

      assert table.entry.selection.selected == []
    end
  end

  describe "reading (Reading)" do
    test "a table that keeps its state takes the new sort and reads for it beside the process" do
      {table, effects, nil} = step(table(), {:sort, "name"})

      assert table.entry.state.sort
      assert table.entry.reading.busy?
      assert read?(effects)
      # the summaries are asked for after the callback
      assert table.entry.footer.summary_due == :changed
    end

    test "a table whose state is in the URL is patched, its state as it was" do
      before = table(Resource, url: "/tasks?other=1")
      {table, effects, nil} = step(before, {:sort, "name"})

      assert table.entry.state == before.entry.state
      assert [{:patch, "/tasks?" <> query}] = effects
      assert %{"other" => "1", "t" => %{"sort" => _}} = Plug.Conn.Query.decode(query)
    end

    test "a page size the table does not offer changes nothing" do
      before = table()
      assert {^before, [], nil} = step(before, {:page_size, "7"})
    end

    test "clearing the filters of a table that has none reads nothing" do
      {table, effects, nil} = step(table(Resource, rejected: %{name: "x"}), :clear_filters)

      assert table.entry.filter == %{rejected: %{}, pending: %{controls: %{}, among: []}}
      assert effects == []
    end

    test "a filter that changes the state is announced and read for" do
      {table, effects, nil} =
        step(table(), {:filter, %{"name" => %{"o" => "contains", "v" => "a"}}})

      assert table.entry.state.filters != %{}
      assert table.entry.status.announce?
      assert read?(effects)
    end

    test "the host's refresh reads the page again as it is, with its summaries" do
      {table, effects, nil} = step(table(), :refresh)

      assert read?(effects)
      assert table.entry.footer.summary_due == :force
    end

    test "a read that comes back is shown: the stream reset with its rows, the panel closed" do
      table = table(Resource, busy?: true, panel: %{kind: :row}, picker: %{name: :owner})
      page = %Query.Page{records: [], total: 0}
      {table, effects, nil} = step(table, {:async, :read, {:ok, {:ok, page}}})

      assert %{
               reading: %{busy?: false, row_count: 0},
               opens: %{panel: nil, picker: nil}
             } = table.entry

      assert {:stream, {:reset, "t:rows", []}} in effects
    end

    test "the summaries that come back are shown" do
      table = table(Resource, summing?: true)
      {table, [], nil} = step(table, {:async, :summary, {:ok, {:ok, %{name: {:ok, 3}}}}})

      assert %{summary: %{name: {:ok, 3}}, summing?: false} = table.entry.footer
    end

    test "the answer of a task of a table that closed is dropped" do
      before = table()
      key = {:ash_data_table, "t", {:read, make_ref()}}

      assert {^before, [], nil} =
               step(before, {:task, key, {:ok, {:ok, %Query.Page{records: []}}}})
    end
  end

  describe "the URL and the argument line (Url)" do
    test "a value is added to an argument given value by value, and focus goes into it" do
      {table, effects, nil} = step(table(Price), {:argument_add, "names"})

      assert table.entry.arguments.lines == %{{nil, :names} => [""]}

      assert effects == [
               {:push, "ash_data_table:focus",
                %{table: "t", cell: Ids.argument_value(Ids.argument("t", "names"), 0)}}
             ]
    end

    test "an argument that is not given value by value gets nothing" do
      before = table(Price)
      assert {^before, [], nil} = step(before, {:argument_add, "term"})
    end

    test "the host's state: a table whose state is in the URL is patched" do
      {_table, effects, nil} =
        step(table(Resource, url: "/tasks"), {:put_state, %{"sort" => "name"}})

      assert [{:patch, "/tasks?" <> _query}] = effects
    end
  end

  describe "nested tables (Nesting)" do
    test "a row expands where the table has expanders: its detail put into the stream again" do
      table = table(Resource, expandable?: true, rows: %{"1" => %{pk: %{id: 1}, rowindex: 2}})
      {table, effects, reply} = step(table, {:expand, "1"})

      assert reply == %{open: true}
      assert table.entry.nesting.open == %{"1" => []}
      assert [{:stream, {:insert, "t:rows", %{}, []}}] = effects
    end

    test "a table without expanders expands nothing" do
      before = table(Resource, rows: %{"1" => %{pk: %{id: 1}, rowindex: 2}})
      assert {^before, [], %{open: false}} = step(before, {:expand, "1"})
    end
  end

  describe "cells (Cells)" do
    test "what is no cell of the table is refused, and nothing is read" do
      before = table(Resource, rows: %{"1" => %{pk: %{id: 1}, rowindex: 2}})

      assert {^before, [], %{ok: false}} = step(before, {:reveal, "1", "nope"})
      assert {^before, [], %{ok: false}} = step(before, {:save, "1", "nope", "x"})
      assert {^before, [], %{ok: false}} = step(before, {:edit, "1", "nope"})
    end

    test "Escape on a cell or a button that has not failed does nothing" do
      before = table()
      assert {^before, [], nil} = step(before, {:discard, "1", "name"})
      assert {^before, [], nil} = step(before, {:dismiss, "1"})
    end
  end

  describe "the picker (Picker)" do
    test "a reference cell of no row opens nothing" do
      before = table()
      assert {^before, [], %{ok: false}} = step(before, {:pick, "1", "owner"})
    end

    test "a choice where no picker is open is none" do
      before = table()
      picked = %{none?: false, confirmed?: false, arguments: nil}

      assert {^before, [], %{ok: false}} = step(before, {:picked, picked})
      assert {^before, [], nil} = step(before, {:chosen, %{name: "Ann"}})
    end

    test "Cancel closes the picker, the panel stays" do
      table = table(Resource, panel: %{kind: :row}, picker: %{name: :owner})

      assert {%{entry: %{opens: %{panel: %{kind: :row}, picker: nil}}}, [], nil} =
               step(table, :picker_cancel)
    end
  end

  describe "the panel (Panel)" do
    test "the page's Open tells the host the row, whatever notify says" do
      table = table(Resource, open_label: "Open", notify: [], rows: %{"1" => %{pk: %{id: 1}}})

      assert {^table, [{:tell, "t", {:row_opened, %{key: %{id: 1}, table: "t"}}}], nil} =
               step(table, {:open, "1"})

      # a key that names no row of the page gets nothing
      assert {^table, [], nil} = step(table, {:open, "2"})
    end

    test "Cancel closes the panel and its picker" do
      table = table(Resource, panel: %{kind: :row}, picker: %{name: :owner})

      assert {%{entry: %{opens: %{panel: nil, picker: nil}}}, [], nil} =
               step(table, :panel_cancel)
    end

    test "a panel's buttons and form where no panel is open do nothing" do
      before = table()
      assert {^before, [], nil} = step(before, {:panel_add, ["tags"]})
      assert {^before, [], nil} = step(before, {:panel_clear, "secret"})
      assert {^before, [], nil} = step(before, {:panel_validate, %{}})
      assert {^before, [], nil} = step(before, {:panel_submit, %{}})
      assert {^before, [], nil} = step(before, {:pick_input, "owner"})
    end
  end

  # The submit of a panel with a file, in two intents split at the files
  # (`Core.Panel`): the checks and the veto, then, inside LiveView's consume,
  # the rest of the write. The table action `ingest` of
  # `AshDataTable.Test.Files` takes a file and says what it read.
  describe "the submit of a panel with a file (Panel)" do
    @upload "t-file-file"

    defp files_table(fields \\ []) do
      model = Model.build(Files)

      table(Files,
        model: model,
        offered: model.table_actions,
        page: %Query.Page{records: [], total: 0},
        authorize?: false
      )
      |> Table.put(fields)
    end

    # LiveView's upload of the field, with its file received
    defp uploads do
      entry = %Phoenix.LiveView.UploadEntry{
        ref: "0",
        upload_ref: "u",
        upload_config: @upload,
        done?: true,
        progress: 100,
        client_name: "pages.csv",
        client_type: "text/csv"
      }

      %{
        @upload => %Phoenix.LiveView.UploadConfig{
          name: @upload,
          ref: "u",
          entries: [entry],
          errors: [],
          max_entries: 1,
          max_file_size: 8_000_000
        }
      }
    end

    defp opened(table) do
      {table, effects, nil} = step(table, {:table_act, "ingest"})
      # the panel opens with an upload for its file field
      assert [{:uploads, {:allow, @upload, _opts}}] = effects
      assert %{kind: :table} = table.entry.opens.panel
      table
    end

    test "past the checks and the veto, the last effect consumes the files: nothing has run" do
      table = opened(files_table())
      context = %{@context | uploads: uploads()}
      {table, effects, nil} = step(table, {:panel_submit, %{}}, context)

      assert [{:uploads, {:consume, "t", [{"file", %{ref: "0"}}], panel, write}}] = effects
      assert is_function(write, 1)
      # the panel is still open, nothing was said, the table reads nothing
      assert %{kind: :table} = table.entry.opens.panel
      assert table.entry.status.announcements == 0
      assert panel.kind == :table
    end

    test "a veto halts before the files: none is consumed, and the panel says why" do
      veto = fn _request -> {:halt, "Not now."} end
      table = opened(files_table(before_action: veto))
      {table, effects, nil} = step(table, {:panel_submit, %{}}, %{@context | uploads: uploads()})

      refute Enum.any?(effects, &match?({:uploads, {:consume, _, _, _, _}}, &1))
      assert %{kind: :table} = table.entry.opens.panel
      assert table.entry.status.announcements == 1
    end

    test "the second intent runs the rest of the write with the files, and shows what came of it" do
      table = opened(files_table())
      context = %{@context | uploads: uploads()}

      {table, [{:uploads, {:consume, "t", _files, panel, write}}], nil} =
        step(table, {:panel_submit, %{}}, context)

      path = Path.join(System.tmp_dir!(), "ash_data_table-#{System.unique_integer([:positive])}")
      File.write!(path, "a,b")
      on_exit(fn -> File.rm(path) end)
      file = %Plug.Upload{path: path, filename: "pages.csv", content_type: "text/csv"}

      {table, effects, nil} = step(table, {:consumed, panel, write, %{"file" => file}}, context)

      # done: the panel closes, the table says what the action returned and reads again
      assert table.entry.opens.panel == nil

      assert %{summary: {:text, :action_result, [action: _, result: "pages.csv: a,b"]}} =
               table.entry.selection.result

      assert read?(effects)
    end

    test "a file LiveView has not received yet runs nothing" do
      table = opened(files_table())
      upload = uploads()[@upload]
      [entry] = upload.entries
      waiting = %{@upload => %{upload | entries: [%{entry | done?: false}]}}

      {_table, effects, nil} = step(table, {:panel_submit, %{}}, %{@context | uploads: waiting})
      assert effects == []
    end
  end

  describe "actions on the selection (Bulk)" do
    test "a run's result, seen, is said no longer" do
      table = table(Resource, result: %{summary: {:text, :bulk_done, []}, failures: []})
      assert {%{entry: %{selection: %{result: nil}}}, [], nil} = step(table, :bulk_seen)
    end

    test "an action that is none of the selection's is refused" do
      before = table()
      assert {^before, [], %{ok: false}} = step(before, {:bulk, "nope"})
    end

    test "an action on the selection without a question or a panel runs at once, beside the process" do
      before = table(Exports)
      key = Ash.UUID.generate()

      before =
        Table.put(before, bulk: Model.bulk_actions(before.entry.model), selected: [key])

      {table, effects, %{ok: true}} = step(before, {:bulk, "export"})

      # the run is a task of the table, with no files; the keys are read
      # again as the person in it, not here
      assert Enum.any?(
               effects,
               &match?({:async, {:ash_data_table, "t", {:bulk, _token}}, _run, []}, &1)
             )

      assert %{action: %{name: :export, selection_argument: :ids}} =
               table.entry.selection.running
    end
  end

  describe "live updates (Updates)" do
    test "a listener's batch waits for the end of the callback" do
      {table, [], nil} = step(table(), {:heard, [{:update, %{id: 1}}]})
      assert table.entry.updates.waiting == [{:update, %{id: 1}}]
    end

    test "Read again reads the page again as it is" do
      {table, effects, nil} = step(table(), :read_again)

      assert read?(effects)
      assert table.entry.footer.summary_due == :force
    end

    test "a row the hook says can go, that is not on its way out, stays" do
      before = table(Resource, rows: %{"1" => %{pk: %{id: 1}, rowindex: 2}})
      assert {^before, [], nil} = step(before, {:left, "1"})
    end
  end

  describe "what a table is told (Told)" do
    test "what it is told is put, and it reads for it beside the process" do
      {table, effects, nil} = step(table(), {:told, %{label: "Records", depth_limit: 1}})

      assert %{told: %{label: "Records"}, nesting: %{depth_limit: 1}} = table.entry
      assert read?(effects)
    end
  end

  describe "the core's own (Live.Core)" do
    test "an event named for a table that is not shown gets the answer of one of another shape" do
      before = table()

      assert {^before, [], %{ok: false}} =
               step(before, {:event, "ash_data_table:other:save", %{}})

      assert {^before, [], nil} = step(before, {:event, "ash_data_table:t:sort", %{"x" => 1}})
    end

    test "an event of the table runs within it" do
      {table, effects, nil} =
        step(table(), {:event, "ash_data_table:t:sort", %{"column" => "name"}})

      assert table.entry.state.sort
      assert read?(effects)
    end

    test "an answer to a ref no table holds does nothing" do
      before = table()
      fun = &AshDataTable.Live.Core.Opener.Host.cancelled/2
      assert {^before, [], nil} = step(before, {:answer, "r0", :any, fun})
    end

    test "the step gives no context and no effects back in its table" do
      {table, _effects, _reply} = step(table(), {:sort, "name"})
      assert %{context: nil, effects: []} = table
    end
  end
end
