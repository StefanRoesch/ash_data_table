defmodule AshDataTable.Live.Core.Files do
  @moduledoc false
  # Files: the uploads of the panel's fields that take a file,
  # what is said of them, and the files the action is given while LiveView
  # holds them. Over the table (stage 9g): what is done to LiveView's
  # uploads is an effect (`{:uploads, …}`, `Live.Core.effects/2`), and
  # what LiveView knows of them is the step's `context` (`uploads`).

  import Phoenix.Component, only: [upload_errors: 1, upload_errors: 2]

  alias AshDataTable.Live.Core
  alias AshDataTable.Panel
  alias AshDataTable.Table

  # ## Files
  #
  # An argument that takes a file has an upload of LiveView's in the panel
  # (`allow_upload/3`), under a name of the argument's own. It is allowed
  # when a panel with such a field first opens and kept from then on: what
  # it is limited to is the same every time.
  #
  # The file is sent when the panel's button is used: LiveView's client
  # sends the files of a form before the form itself. The action then runs
  # while LiveView still holds the file (`consume_uploaded_entry/3`, in
  # the adapter: the second intent of a submit, `Core.Panel`), and is given
  # it as a `Plug.Upload`, which is what Ash takes for a file from a web
  # request: with the path LiveView wrote it to, the name the browser
  # gave, and its content type. After that the file is LiveView's to take
  # away, whatever the action made of it: a file is given once. The browser
  # shows the same: LiveView's client empties the file input once the file
  # is sent, so a panel that stays open, with what the action said, asks
  # for the file again. What a panel leaves behind that went without its
  # button having been used is given up when the next panel opens
  # (`allowed/2`).
  #
  # What the action of a panel said of its files, and the entries it was
  # given, are the panel's (`AshDataTable.Panel`); the adapter of the panel
  # (`AshDataTable.Live.Core.Panel`) puts it into the entry.

  # A panel is opened: with an upload for each of its fields that takes a
  # file, and without a file that an earlier panel left behind. A panel that
  # goes without its button having been used (Cancel, a new read of the
  # table) leaves the file a person chose with its upload, where nothing is
  # sent of it and nothing shows it; it is given up here, before the next
  # panel is shown, but for those the open panel's action was given.
  def allowed(%Table{} = table, panel) do
    table = drop_files(table)

    Enum.reduce(Panel.file_inputs(panel), table, fn input, table ->
      name = upload_name(table.entry.id, input)

      # allowed once, and again after a table of the same id closed and
      # gave it up (`AshDataTable.Live.Registry.close/2`): the adapter
      # allows only an upload LiveView does not have allowed
      opts = [
        accept: input.upload.accept,
        max_entries: 1,
        max_file_size: input.upload.max_file_size
      ]

      table
      |> Core.effect({:uploads, {:allow, name, opts}})
      |> Table.put(uploads: Enum.uniq([name | table.entry.uploads]))
    end)
  end

  # Gives up the files of the panel's uploads: those a person chose and no
  # action was given. What an action was given is LiveView's to take away.
  # Only this table's: the tables of a page share one LiveView, and a file
  # chosen in another table's open panel is that panel's.
  defp drop_files(%{entry: %{uploads: []}} = table), do: table

  defp drop_files(%{entry: %{opens: %{panel: panel}, uploads: names}} = table),
    do: Core.effect(table, {:uploads, {:drop, names, Panel.spent(panel)}})

  # Whether a panel's action can run with the files of its uploads: `:ok`;
  # not while LiveView does not take a file (`{:refused, refused}`, what it
  # says of each), or has not received one (`:waiting`).
  def filed(%Table{context: %{uploads: uploads}, entry: %{id: id}}, panel) do
    inputs = Panel.file_inputs(panel)
    refused = refused(uploads, id, panel)

    # LiveView's client sends the files before the form; a form that
    # comes without them was not sent by it
    waiting? =
      Enum.any?(inputs, &match?(%{done?: false}, entry(upload_of(uploads, id, &1))))

    cond do
      inputs != [] and refused != [] -> {:refused, refused}
      waiting? -> :waiting
      true -> :ok
    end
  end

  @doc """
  The files of the panel to consume before its action runs, by the
  argument's name: each that LiveView has received, with its entry
  (`{name, entry}`). A field without a file gives none.
  """
  def consumed(%Table{context: %{uploads: uploads}, entry: %{id: id}}, panel) do
    for input <- Panel.file_inputs(panel),
        %{done?: true} = entry <- [entry(upload_of(uploads, id, input))],
        do: {Atom.to_string(input.name), entry}
  end

  # The files an action has been given are LiveView's to take away: the
  # entries of every file of the panel's uploads, once the write got past
  # its checks and its veto (it was consumed), which the panel keeps
  # (`AshDataTable.Panel.spend/2`).
  def given(%Table{} = table, panel),
    do: for({_name, entry} <- consumed(table, panel), do: entry.ref)

  @doc """
  Copies of the files for a run that outlasts the event: temporary files
  of this process until the run's process is given them before its work
  starts (`Registry.owned/1`), and gone when their process is
  (`Plug.Upload.random_file!/1`).
  """
  def copies(files) do
    for {name, %Plug.Upload{path: path} = file} <- files, into: %{} do
      copy = Plug.Upload.random_file!("ash_data_table")
      File.cp!(path, copy)
      {name, %{file | path: copy}}
    end
  end

  # What LiveView says of the files of a panel that it does not take: by
  # field, what is shown at the field. `uploads` are the LiveView's, `id`
  # the table's (a step's `context` holds them).
  def refused(uploads, id, panel) do
    for input <- Panel.file_inputs(panel),
        texts = upload_errors_of(upload_of(uploads, id, input)),
        texts != [],
        do: {input.label, texts}
  end

  # What LiveView does not take of the files, read out (`Core.say/2`).
  def say_files(table, []), do: table

  def say_files(table, refused) do
    said =
      for {label, texts} <- refused,
          do: {:text, :error_on_field, field: label, message: {:join, " ", texts}}

    Core.say(table, {:join, "; ", said})
  end

  # The name of the upload of a field: with the table's id before the
  # argument's name. LiveView wants the name of an upload to be one of a
  # kind in its process, and the tables of a page are all of one process:
  # two tables placed in a LiveView, a table and the tables nested in it,
  # a picker. Two of them can have an action with an argument of the same
  # name, and each a file for it at the same time.
  @doc "What the upload of a file field is called among the LiveView's uploads."
  def upload_name(id, %{name: name}), do: id <> "-file-" <> Atom.to_string(name)

  # The upload of a field, as LiveView keeps it; nil for any other field.
  def upload_of(uploads, id, %{editor: :file} = input) when is_map(uploads),
    do: Map.get(uploads, upload_name(id, input))

  def upload_of(_uploads, _id, _input), do: nil

  # The file of an upload, which holds one at most, as LiveView knows it
  # (an entry). A file that another has taken the place of is still among
  # the upload's entries until LiveView has let go of it: it is none of the
  # field's any more.
  defp entry(%{entries: entries}), do: Enum.find(entries, &(not &1.cancelled?))

  defp entry(_none), do: nil

  def entry_ref(upload), do: with(%{ref: ref} <- entry(upload), do: ref)

  # What an upload's file is refused for, as a person reads it.
  #
  # The field takes one file, and a browser gives it one. A file that
  # another has taken the place of is not counted: LiveView lists it for a
  # moment longer, and says "too many" of the two.
  defp upload_errors_of(nil), do: []

  defp upload_errors_of(upload) do
    reasons =
      case Enum.reject(upload.entries, & &1.cancelled?) do
        [entry] -> upload_errors(upload, entry)
        [] -> []
        several -> upload_errors(upload) ++ Enum.flat_map(several, &upload_errors(upload, &1))
      end

    for reason <- Enum.uniq(reasons) do
      case reason do
        :too_large -> {:text, :upload_too_large, limit: size(upload.max_file_size)}
        :not_accepted -> {:text, :upload_not_accepted, []}
        _failure -> {:text, :upload_failed, []}
      end
    end
  end

  # A number of bytes as a size, in the units LiveView counts in.
  defp size(bytes) when bytes >= 1_000_000, do: "#{number(bytes / 1_000_000)} MB"

  defp size(bytes) when bytes >= 1_000, do: "#{number(bytes / 1_000)} kB"

  defp size(bytes), do: "#{bytes} B"

  defp number(amount) do
    rounded = Float.round(amount, 1)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  # What the panel is given of its file fields, by name: the upload of
  # each, and what is said of its file at the field (`said_of/4`).
  def panel_files(%{panel: panel, id: id}, uploads) do
    for input <- Panel.file_inputs(panel), into: %{} do
      {input.name,
       %{upload: upload_of(uploads, id, input), errors: said_of(panel, input, id, uploads)}}
    end
  end

  # What is said at each file field of the panel, by name (`said_of/4`).
  def files_said(held, uploads),
    do: Map.new(panel_files(held, uploads), fn {name, %{errors: errors}} -> {name, errors} end)

  # What is read out of a field when the panel stays open: for a file, what
  # is shown at its field; for the rest, what the action said.
  def said_of(panel, %{editor: :file} = input, id, uploads) do
    upload = upload_of(uploads, id, input)
    upload_errors_of(upload) ++ Panel.file_errors(panel, input, entry_ref(upload))
  end

  def said_of(panel, input, _id, _uploads), do: Panel.errors_at(panel, input)
end
