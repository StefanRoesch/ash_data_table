defmodule AshDataTable.DownloadTest do
  @moduledoc """
  A file a generic action returned (`returns Ash.Type.File`), read for the
  person's browser to save (`AshDataTable.Download`).
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias AshDataTable.Download
  alias AshDataTable.Model

  @action %Model.Action{name: :export, label: "Export", type: :action, file?: true}

  @moduletag :tmp_dir

  describe "of/2" do
    test "reads a file on disk whole, named after it, typed as bytes where it says nothing",
         %{tmp_dir: dir} do
      path = Path.join(dir, "report.csv")
      File.write!(path, "a,b\r\n1,2\r\n")

      assert {:ok, %Download{name: "report.csv", type: "application/octet-stream", data: data}} =
               Download.of(@action, Ash.Type.File.from_path(path))

      assert data == "a,b\r\n1,2\r\n"
    end

    test "takes what Ash casts into a file, and an empty one" do
      {:ok, device} = StringIO.open("")

      # a device has no name: the file is named after the action
      assert {:ok, %Download{name: "export", data: ""}} =
               Download.of(@action, Ash.Type.File.from_io(device))
    end

    test "is none for nothing, and an error for what is no file, which is logged" do
      assert Download.of(@action, nil) == :none

      log =
        capture_log(fn ->
          assert Download.of(@action, 42) == {:error, {:text, :action_failed, []}}
        end)

      assert log =~ "the action `export` returns a file, and it returned 42, which is no file"
    end
  end

  describe "told/1 and pushed/2" do
    test "tell the page its name and type, and push its content in Base64" do
      download = %Download{name: "tasks.csv", type: "text/csv", data: "id\r\n"}

      assert Download.told(download) == %{filename: "tasks.csv", content_type: "text/csv"}

      assert Download.pushed(download, "task") == %{
               table: "task",
               name: "tasks.csv",
               type: "text/csv",
               data: Base.encode64("id\r\n")
             }
    end
  end
end
