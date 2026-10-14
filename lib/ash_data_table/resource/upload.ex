defmodule AshDataTable.Resource.Upload do
  @moduledoc """
  An `upload` declared in a resource's `table` block: what the upload of an
  argument that takes a file is limited to in the action panel.

  This is the declaration as written, as `AshDataTable.Resource.Info.uploads/1`
  returns it: an option that was not given is `nil`.
  """

  defstruct [:name, :accept, :max_file_size, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom,
          accept: [String.t()] | nil,
          max_file_size: pos_integer | nil
        }

  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "The argument: a public argument of the type `Ash.Type.File` of an action the table offers (an `action` of the block, or its `create_action`). It applies to every such action that has an argument of this name."
    ],
    accept: [
      type: {:list, :string},
      doc:
        "The kinds of file the upload takes: file name extensions (`\".csv\"`) and MIME types (`\"text/csv\"`, `\"image/*\"`), as `Phoenix.LiveView.allow_upload/3` takes them. Defaults to any file."
    ],
    max_file_size: [
      type: :pos_integer,
      doc: "The largest file the upload takes, in bytes. Defaults to LiveView's own limit, 8 MB."
    ]
  ]

  @doc false
  def schema, do: @schema
end
