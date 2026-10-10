defmodule AshTable.Sensitive do
  @moduledoc false
  # What a table does with a field its resource declares `sensitive?`: an
  # attribute, a calculation or an aggregate, and an argument of an action.
  # Shared by the verifiers (which report a mistake), the table model (which
  # builds on the answer) and the table itself.
  #
  # `sensitive?` is no access rule: Ash keeps such a value out of what it
  # logs and inspects, and whoever the field policies allow reads it. A
  # table takes it to mean that the value is not shown until somebody asks
  # for it:
  #
  #   * a cell shows a mask, the same for every value, and the value is not
  #     in the page: a record is given to a row with every sensitive value
  #     in it replaced (`scrub/1`). A cell without a value is empty, as any
  #     cell is: only that there is nothing is said;
  #   * the value of one cell is read again when a person asks for it, as
  #     that person;
  #   * what is typed for one is hidden as it is typed, which a table can
  #     do for text and for a number, and for nothing else (`typed?/1`);
  #   * a table neither sorts nor filters by one: the order of the rows, and
  #     which of them a filter leaves, would say what the mask hides.

  defmodule Masked do
    @moduledoc false
    # What stands in a record for a sensitive value that is there.
    defstruct []

    @type t :: %__MODULE__{}
  end

  # the editors that can hide what is typed: one line, in a password input
  @typed [:text, :number]

  @doc "What a cell shows in place of a sensitive value: the same for every value."
  @spec mask() :: String.t()
  def mask, do: "••••••"

  @doc "Whether a field, an argument or a column says that it is sensitive."
  @spec sensitive?(term) :: boolean
  def sensitive?(%{sensitive?: true}), do: true
  def sensitive?(_field), do: false

  @doc """
  Whether a table hides what is typed into an editor of that kind: text and
  numbers, which are typed as one line. Every other editor shows what it
  holds (a box, a menu, a date), so a sensitive field has none of them.
  """
  @spec typed?(atom | nil) :: boolean
  def typed?(editor), do: editor in @typed

  @doc """
  Whether a sensitive field holds nothing: such a cell is empty and has
  nothing to show.
  """
  @spec empty?(term) :: boolean
  def empty?(nil), do: true
  def empty?(""), do: true
  def empty?([]), do: true
  def empty?(%Ash.NotLoaded{}), do: true
  def empty?(_value), do: false

  @doc """
  A record as a table keeps it for a row: with every sensitive value in it
  replaced by a `Masked`. That is every attribute, calculation and aggregate
  its resource declares `sensitive?`, a calculation loaded under another
  name among them; the same in every record loaded with it, and in every
  value of an embedded resource it holds.

  Left as they are: a value that is not there (`empty?/1`), one Ash has
  hidden from the person (`Ash.ForbiddenField`), and the primary key, by
  which a row is told apart.
  """
  @spec scrub(term) :: term
  def scrub(%Masked{} = masked), do: masked
  def scrub(%Ash.ForbiddenField{} = hidden), do: hidden
  def scrub(%Ash.NotLoaded{} = not_loaded), do: not_loaded
  def scrub(%Ash.Union{value: value} = union), do: %{union | value: scrub(value)}
  def scrub(values) when is_list(values), do: Enum.map(values, &scrub/1)

  def scrub(%resource{} = record) do
    if Ash.Resource.Info.resource?(resource) do
      names = sensitive_names(resource)
      key = Ash.Resource.Info.primary_key(resource)

      record
      |> Map.from_struct()
      |> Enum.reduce(record, fn
        {:calculations, %{} = loaded}, record ->
          Map.put(record, :calculations, scrub_named(loaded, resource))

        {:aggregates, %{} = loaded}, record ->
          Map.put(record, :aggregates, scrub_named(loaded, resource))

        {name, value}, record ->
          cond do
            name in names and name not in key -> Map.put(record, name, masked(value))
            scrubbed?(value) -> Map.put(record, name, scrub(value))
            true -> record
          end
      end)
    else
      record
    end
  end

  def scrub(value), do: value

  @doc """
  The same, for the record of a row of a table with these columns
  (`AshTable.Model.Column`): a sensitive calculation that a column shows
  under another name (`as`) is under that name among the record's
  `calculations`, where its own name does not find it.
  """
  @spec scrub(term, [map]) :: term
  def scrub(%_{} = record, columns) when is_list(columns) do
    record = scrub(record)

    renamed =
      for %{sensitive?: true, kind: :calculation, name: name, field: field} <- columns,
          name != field,
          do: name

    case {renamed, record} do
      {[_ | _], %{calculations: %{} = loaded}} ->
        loaded =
          Map.new(loaded, fn {name, value} ->
            {name, if(name in renamed, do: masked(value), else: value)}
          end)

        %{record | calculations: loaded}

      _nothing_renamed ->
        record
    end
  end

  def scrub(record, _columns), do: scrub(record)

  # What Ash keeps beside a record's own fields, by the names the resource
  # has for them.
  defp scrub_named(loaded, resource) do
    names = sensitive_names(resource)

    Map.new(loaded, fn {name, value} ->
      {name, if(name in names, do: masked(value), else: scrub(value))}
    end)
  end

  # only what can hold a record or an embedded value is looked into
  defp scrubbed?(value), do: is_list(value) or is_struct(value)

  defp masked(%Ash.ForbiddenField{} = hidden), do: hidden
  defp masked(%Ash.NotLoaded{} = not_loaded), do: not_loaded
  defp masked(value), do: if(empty?(value), do: value, else: %Masked{})

  defp sensitive_names(resource) do
    for field <-
          Ash.Resource.Info.attributes(resource) ++
            Ash.Resource.Info.calculations(resource) ++
            Ash.Resource.Info.aggregates(resource),
        sensitive?(field),
        do: field.name
  end
end
