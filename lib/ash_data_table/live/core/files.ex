defmodule AshDataTable.Live.Core.Files do
  @moduledoc false
  # Files: the uploads of the panel's fields that take a file,
  # what is said of them, and the action run while LiveView holds them.

  import Phoenix.LiveView
  import Phoenix.Component, only: [upload_errors: 1, upload_errors: 2]

  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Panel

  # ## Files
  #
  # An argument that takes a file has an upload of LiveView's in the panel
  # (`allow_upload/3`), under a name of the argument's own. It is allowed
  # when a panel with such a field first opens and kept from then on: what
  # it is limited to is the same every time.
  #
  # The file is sent when the panel's button is used: LiveView's client
  # sends the files of a form before the form itself. The action then runs
  # while LiveView still holds the file (`consume_uploaded_entry/3`), and
  # is given it as a `Plug.Upload`, which is what Ash takes for a file from
  # a web request: with the path LiveView wrote it to, the name the browser
  # gave, and its content type. After that the file is LiveView's to take
  # away, whatever the action made of it: a file is given once. The browser
  # shows the same: LiveView's client empties the file input once the file
  # is sent, so a panel that stays open, with what the action said, asks
  # for the file again. What a panel leaves behind that went without its
  # button having been used is given up when the next panel opens
  # (`opened/2`).

  def file_inputs(%{inputs: inputs}), do: Enum.filter(inputs, &(&1.editor == :file))

  # A panel is opened: with an upload for each of its fields that takes a
  # file, and without a file that an earlier panel left behind. A panel that
  # goes without its button having been used (Cancel, a new read of the
  # table) leaves the file a person chose with its upload, where nothing is
  # sent of it and nothing shows it; it is given up here, before the next
  # panel is shown.
  def opened(socket, panel) do
    socket = drop_files(socket)

    socket =
      Enum.reduce(file_inputs(panel), socket, fn input, socket ->
        name = upload_name(Core.table(socket).entry.id, input)

        # allowed once, and again after a table of the same id closed and
        # gave it up (`AshDataTable.Live.Registry.close/2`); this table's
        # either way, also when the table before it could not give it up
        socket =
          if match?(%{^name => %{allowed?: true}}, socket.assigns[:uploads] || %{}),
            do: socket,
            else:
              allow_upload(socket, name,
                accept: input.upload.accept,
                max_entries: 1,
                max_file_size: input.upload.max_file_size
              )

        Core.put(socket, uploads: Enum.uniq([name | Core.table(socket).entry.uploads]))
      end)

    Core.put(socket, panel: panel)
  end

  # Gives up the files of the panel's uploads: those a person chose and no
  # action was given. What an action was given is LiveView's to take away.
  # Only this table's: the tables of a page share one socket, and a file
  # chosen in another table's open panel is that panel's.
  defp drop_files(socket) do
    %{spent: spent, uploads: names} = Core.table(socket).entry
    uploads = socket.assigns[:uploads] || %{}

    Enum.reduce(names, socket, fn name, socket ->
      Enum.reduce(uploads[name].entries, socket, fn entry, socket ->
        if entry.cancelled? or entry.ref in spent,
          do: socket,
          else: cancel_upload(socket, name, entry.ref)
      end)
    end)
  end

  # Runs a panel's action with the files of its uploads (`submit/3`).
  # Nothing runs while LiveView does not take a file, or has not received
  # one: that is said, and the panel stays.
  def filed(socket, panel, params) do
    inputs = file_inputs(panel)
    refused = refused_files(socket, panel)

    # LiveView's client sends the files before the form; a form that
    # comes without them was not sent by it
    waiting? =
      Enum.any?(inputs, fn input ->
        match?(
          %{done?: false},
          entry(upload_of(socket.assigns[:uploads], Core.table(socket).entry.id, input))
        )
      end)

    cond do
      inputs != [] and refused != [] ->
        {:noreply,
         socket |> Core.put(panel: %{panel | refused_files: refused}) |> say_files(refused)}

      waiting? ->
        {:noreply, Core.say(socket, {:text, :upload_failed, []})}

      true ->
        Panel.submit(socket, panel, params)
    end
  end

  # What the action of a panel is run inside (`with_files` of
  # `AshDataTable.Operation.Input`): each file in turn, the action inside the
  # last, by the argument's name. LiveView takes a file away when the
  # function it is given for it returns. A run on a selection outlasts the
  # event, which is as long as LiveView keeps the file: it runs with a copy,
  # which is this process's until the run is done (`Plug.Upload`).
  def attach(socket, panel, run) do
    attach(socket, file_inputs(panel), %{}, fn files ->
      run.(if panel.kind == :bulk, do: copies(files), else: files)
    end)
  end

  def attach(_socket, [], files, run), do: run.(files)

  def attach(socket, [input | rest], files, run) do
    case entry(upload_of(socket.assigns[:uploads], Core.table(socket).entry.id, input)) do
      %{done?: true} = entry ->
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          file = %Plug.Upload{
            path: path,
            # a name is a name: never a way to somewhere
            filename: Path.basename(entry.client_name),
            content_type: entry.client_type
          }

          # the file is gone when this returns: its entry is LiveView's to drop
          {:ok, attach(socket, rest, Map.put(files, Atom.to_string(input.name), file), run)}
        end)

      _no_file ->
        attach(socket, rest, files, run)
    end
  end

  # The files an action has been given are LiveView's to take away: every
  # file of the panel's uploads, once the write got past its checks and
  # its veto (`attach/3` ran).
  def spend(socket, _panel, result) when result == :refused or elem(result, 0) == :halted,
    do: socket

  def spend(socket, panel, _result) do
    given =
      for input <- file_inputs(panel),
          %{done?: true, ref: ref} <-
            [entry(upload_of(socket.assigns[:uploads], Core.table(socket).entry.id, input))],
          do: ref

    Core.put(socket, spent: MapSet.union(Core.table(socket).entry.spent, MapSet.new(given)))
  end

  # Copies of the files for a run that outlasts the event: temporary files
  # of this process, which are gone when it is (`Plug.Upload.random_file!/1`).
  defp copies(files) do
    for {name, %Plug.Upload{path: path} = file} <- files, into: %{} do
      copy = Plug.Upload.random_file!("ash_data_table")
      File.cp!(path, copy)
      {name, %{file | path: copy}}
    end
  end

  def drop_copies(socket) do
    Enum.each(Core.table(socket).entry.running_files, &File.rm/1)
    Core.put(socket, running_files: [])
  end

  # What LiveView says of the files of a panel that it does not take: by
  # field, what is shown at the field.
  defp refused_files(socket, panel) do
    for input <- file_inputs(panel),
        texts =
          upload_errors_of(
            upload_of(socket.assigns[:uploads], Core.table(socket).entry.id, input)
          ),
        texts != [],
        do: {input.label, texts}
  end

  # Read out when it changes: a file is refused as it is chosen, without
  # the panel's button having been used.
  def say_refused_files(socket) do
    %{panel: panel} = Core.table(socket).entry

    case refused_files(socket, panel) do
      refused when refused == panel.refused_files ->
        socket

      refused ->
        socket |> Core.put(panel: %{panel | refused_files: refused}) |> say_files(refused)
    end
  end

  defp say_files(socket, []), do: socket

  defp say_files(socket, refused) do
    said =
      for {label, texts} <- refused,
          do: {:text, :error_on_field, field: label, message: {:join, " ", texts}}

    Core.say(socket, {:join, "; ", said})
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

  # What the action said of the file of a field: what it said when it last
  # ran, of the file it was given then or of having been given none, until
  # another file is chosen. A file that was chosen and not yet given has
  # had nothing said of it.
  defp file_errors(panel, input, upload) do
    case {Map.get(panel.file_errors, input.name), entry_ref(upload)} do
      # the file the action was given, for as long as LiveView lists it
      {{given, texts}, given} -> texts
      # no file since
      {{_given, texts}, nil} -> texts
      _another_file_or_never_run -> []
    end
  end

  # What the panel is given of its file fields, by name: the upload of
  # each, and what is said of its file at the field (`said_of/4`).
  def panel_files(%{panel: panel, id: id}, uploads) do
    for input <- file_inputs(panel), into: %{} do
      {input.name,
       %{upload: upload_of(uploads, id, input), errors: said_of(panel, input, id, uploads)}}
    end
  end

  # What is said at each file field of the panel, by name (`said_of/4`).
  def files_said(entry, uploads),
    do: Map.new(panel_files(entry, uploads), fn {name, %{errors: errors}} -> {name, errors} end)

  # What is read out of a field when the panel stays open: for a file, what
  # is shown at its field; for the rest, what the action said.
  def said_of(panel, %{editor: :file} = input, id, uploads) do
    upload = upload_of(uploads, id, input)
    upload_errors_of(upload) ++ file_errors(panel, input, upload)
  end

  def said_of(panel, input, _id, _uploads), do: Map.get(panel.errors, input && input.name, [])
end
