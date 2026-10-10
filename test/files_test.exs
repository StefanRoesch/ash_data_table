defmodule AshTable.FilesTest do
  @moduledoc """
  Boundary 2: what a table makes of an argument that takes a file
  (`Ash.Type.File`): the input it is in the action panel, what its upload is
  limited to, and how the file reaches the action.
  """
  use ExUnit.Case, async: false

  alias AshTable.Act
  alias AshTable.Bulk
  alias AshTable.Model
  alias AshTable.Resource.Acting
  alias AshTable.Resource.Uploading
  alias AshTable.Test.Files

  defp model, do: Model.build(Files)
  defp action(name), do: Enum.find(model().actions ++ model().table_actions, &(&1.name == name))
  defp input(action, name), do: Enum.find(action(action).inputs, &(&1.name == name))

  # A file as the table's upload gives it to an action.
  defp file(text, name \\ "notes.txt") do
    path = Path.join(System.tmp_dir!(), "ash_table-#{System.unique_integer([:positive])}")
    File.write!(path, text)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: name, content_type: "text/plain"}
  end

  describe "an argument that takes a file" do
    test "is an input with a file upload, of an action on a record, on the table, and of the create action" do
      assert %{kind: :argument, editor: :file, cell_type: :other, required?: true} =
               input(:attach, :file)

      assert %{editor: :file, required?: true} = input(:measure, :against)
      assert %{editor: :file, required?: true} = input(:ingest, :file)

      assert Enum.map(model().create.inputs, &{&1.name, &1.editor, &1.required?}) == [
               {:title, :text, false},
               {:file, :file, false}
             ]
    end

    test "is the type itself, or a NewType of it; never an array of files" do
      defmodule Scan do
        use Ash.Type.NewType, subtype_of: :file
      end

      assert Acting.file?(Ash.Type.File)
      assert Acting.file?(:file)
      assert Acting.file?(Scan)
      refute Acting.file?({:array, Ash.Type.File})
      refute Acting.file?(Ash.Type.String)

      # an array of files has no field: it is left out where it can be
      refute :several in Enum.map(action(:ingest).inputs, & &1.name)
    end

    test "opens the action panel, also where it is the only input and can be left out" do
      assert [%{name: :note, editor: :file, required?: false}] = action(:annotate).inputs
      assert action(:annotate).panel?
      assert action(:attach).panel?
    end

    test "leaves the action one that runs on several rows" do
      assert Enum.map(Model.bulk_actions(model()), & &1.name) == [
               :attach,
               :pair,
               :annotate,
               :measure
             ]
    end

    test "has no input in the argument line: the table reads without it" do
      assert model().arguments == []
    end
  end

  describe "what an upload is limited to" do
    test "what the block says for the argument's name, in every action that has it" do
      limits = %{accept: [".csv", "text/plain"], max_file_size: 2_000}

      assert input(:attach, :file).upload == limits
      assert input(:ingest, :file).upload == limits
      assert Enum.find(model().create.inputs, &(&1.name == :file)).upload == limits
    end

    test "LiveView's own limits for what the block leaves out: any kind of file, 8 MB" do
      assert input(:pair, :front).upload == %{accept: :any, max_file_size: 50_000_000}
      assert input(:pair, :rear).upload == %{accept: :any, max_file_size: 8_000_000}
      assert Uploading.limits(Files, :unheard_of) == %{accept: :any, max_file_size: 8_000_000}
    end

    test "is said of no other input" do
      assert input(:attach, :title).upload == nil
    end
  end

  describe "how a file reaches the action" do
    setup do
      record = Ash.Seed.seed!(Files, %{title: "Page 1"})
      on_exit(fn -> AshTable.Test.Ets.stop(Files) end)
      %{record: record, key: %{id: record.id}}
    end

    test "never from what the form sent: the table gives it", %{key: key} do
      assert Act.values(action(:attach).inputs, %{"title" => "x", "file" => "/etc/hostname"}) ==
               %{"title" => "x"}

      # the action runs without one, and says so
      assert {:error, %AshPhoenix.Form{} = form} =
               Act.submit_row(
                 model(),
                 action(:attach),
                 key,
                 %{"file" => "/etc/hostname"},
                 "panel",
                 authorize?: false
               )

      assert Act.errors(form, model(), action(:attach).inputs)[:file] == ["is required"]
    end

    test "to an action on a record, as what Ash takes for a file from a web request", %{key: key} do
      assert {:ok, record} =
               Act.submit_row(model(), action(:attach), key, %{"title" => "Page one"}, "panel",
                 authorize?: false,
                 files: %{"file" => file("hello", "notes.txt")}
               )

      assert %{
               title: "Page one",
               content: "hello",
               file_name: "notes.txt",
               file_type: "text/plain"
             } =
               record
    end

    test "to a generic action in a row, beside the row's key", %{key: key} do
      assert {:done, 5} =
               Act.submit_row(model(), action(:measure), key, %{}, "panel",
                 authorize?: false,
                 files: %{"against" => file("12345")}
               )
    end

    test "to a table action, as what the table gives itself" do
      assert {:done, "pages.csv: a,b"} =
               Act.submit_generic(
                 model(),
                 action(:ingest),
                 %{},
                 %{"file" => file("a,b", "pages.csv")},
                 "panel",
                 authorize?: false
               )
    end

    test "to the create action" do
      assert {:ok, %{title: "New", content: "fresh"}} =
               Act.submit_create(
                 model(),
                 model().create,
                 %{"title" => "New"},
                 %{"file" => file("fresh")},
                 "panel",
                 authorize?: false
               )
    end

    test "to every record of a selection: the same file each time", %{record: record} do
      other = Ash.Seed.seed!(Files, %{title: "Page 2"})
      input = %{"title" => "Both", "file" => file("shared")}

      assert %{done: 2, failed: [], failures: []} =
               Bulk.run(model(), action(:attach), {:rows, [record.id, other.id]}, input,
                 authorize?: false
               )

      for %{id: id} <- [record, other] do
        assert %{title: "Both", content: "shared"} = Ash.get!(Files, id, authorize?: false)
      end

      assert %{done: 2} =
               Bulk.run(
                 model(),
                 action(:measure),
                 {:rows, [record.id, other.id]},
                 %{"against" => file("12")},
                 authorize?: false
               )
    end
  end
end
