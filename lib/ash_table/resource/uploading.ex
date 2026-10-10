defmodule AshTable.Resource.Uploading do
  @moduledoc false
  # What the upload of an argument that takes a file is limited to. Shared
  # by the verifiers (which report a mistake) and the table model (which
  # builds on the answer).
  #
  # `Ash.Type.File` is the type of an argument, never of an attribute: Ash
  # stores no file. It has no constraints, so nothing in the resource says
  # how large a file may be or of which kind. The action panel gives such an
  # argument an upload of LiveView's (`Phoenix.LiveView.allow_upload/3`),
  # which has limits of its own: one file of any kind, of 8 MB at most. An
  # `upload` of the block sets other ones for an argument, by its name, in
  # every action of the table that has it. What the action makes of the
  # file is the action's to say, as of any input.

  alias Ash.Resource.Info
  alias AshTable.Resource.Acting
  alias AshTable.Resource.Info, as: TableInfo

  # LiveView's own limit (`Phoenix.LiveView.UploadConfig`)
  @max_file_size 8_000_000

  # the kinds of file a browser knows by a wildcard
  @wildcards ~w(audio/* image/* video/*)

  @type limits :: %{accept: :any | [String.t()], max_file_size: pos_integer}

  @type reason ::
          {:no_file_argument, atom}
          | {:not_a_file, atom, atom, Ash.Type.t()}
          | {:empty_accept, atom}
          | {:invalid_accept, atom, String.t()}

  @doc """
  What the upload of the argument `name` is limited to: what the `upload`
  of the block says for it, else LiveView's own limits.
  """
  @spec limits(Ash.Resource.t() | Spark.Dsl.t(), atom) :: limits
  def limits(resource, name) do
    declared = Enum.find(TableInfo.uploads(resource), &(&1.name == name))

    %{
      accept: (declared && declared.accept) || :any,
      max_file_size: (declared && declared.max_file_size) || @max_file_size
    }
  end

  @doc """
  What is wrong with an `upload` of the block, each mistake with the option
  it is about (nil for the declaration as a whole).

  It names a public argument that takes a file, of an action the table
  offers: an `action` of the block, or its `create_action`. What it accepts
  is what `Phoenix.LiveView.allow_upload/3` takes, which raises for anything
  else when the panel opens: a file name extension with a known MIME type,
  a known MIME type, or one of the wildcards for media files.
  """
  @spec mistakes(Ash.Resource.t() | Spark.Dsl.t(), AshTable.Resource.Upload.t()) ::
          [{:accept | nil, reason}]
  def mistakes(resource, %{name: name} = declaration) do
    arguments =
      for action <- offered(resource),
          %{name: ^name, public?: true} = argument <- action.arguments,
          do: {action, argument}

    named =
      case {arguments, Enum.find(arguments, fn {_action, argument} -> file?(argument) end)} do
        {[], _none} ->
          [{nil, {:no_file_argument, name}}]

        {[{action, argument} | _], nil} ->
          [{nil, {:not_a_file, name, action.name, argument.type}}]

        {_arguments, _file} ->
          []
      end

    accepted =
      case declaration.accept do
        nil ->
          []

        [] ->
          [{:accept, {:empty_accept, name}}]

        accept ->
          for kind <- accept, not kind?(kind), do: {:accept, {:invalid_accept, name, kind}}
      end

    named ++ accepted
  end

  defp file?(argument), do: Acting.file?(argument.type)

  # The actions the table offers a person: those its `action`s name, and
  # its create action.
  defp offered(resource) do
    named =
      for %{name: name} <- TableInfo.actions(resource),
          action = Info.action(resource, name),
          do: action

    case TableInfo.table_create_action(resource) do
      {:ok, name} -> named ++ List.wrap(Info.action(resource, name))
      :error -> named
    end
  end

  defp kind?(kind) when kind in @wildcards, do: true
  defp kind?("." <> extension), do: extension != "" and MIME.has_type?(extension)
  defp kind?(kind), do: MIME.extensions(kind) != []

  @doc "What is wrong with a declared upload, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:no_file_argument, name}),
    do:
      "No action of the table has a public argument named `#{name}`. An `upload` names an " <>
        "argument of the type `Ash.Type.File` of an action the table offers: an `action` of " <>
        "the block, or its `create_action`."

  def message({:not_a_file, name, action, type}),
    do:
      "The argument `#{name}` of the action `#{action}` is of the type #{inspect(type)}, and " <>
        "takes no file. An `upload` says what the upload of an argument of the type " <>
        "`Ash.Type.File` is limited to."

  def message({:empty_accept, name}),
    do:
      "The upload of `#{name}` says `accept []`, which takes no file at all. Name the kinds " <>
        "of file it takes, or leave `accept` out: it then takes any file."

  def message({:invalid_accept, name, kind}),
    do:
      "The upload of `#{name}` accepts #{inspect(kind)}, which is no kind of file LiveView " <>
        "knows. `accept` takes file name extensions with a known MIME type (\".csv\"), MIME " <>
        "types (\"text/csv\"), and the wildcards \"audio/*\", \"image/*\" and \"video/*\". " <>
        "Another extension is made known with `config :mime, :types`."
end
