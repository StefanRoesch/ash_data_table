defmodule AshDataTable.Present do
  @moduledoc false
  # What a part draws, made of what the core holds
  # (docs/architecture/target.md 4.3). The core keeps keys and the
  # panel's form; this turns them into the rows of the stream, the fields of
  # the action panel and the picker, and a part draws from these and from
  # nothing else: it is never given a record, an `AshPhoenix.Form` or a
  # changeset.
  #
  # Values, not texts: the words are made beside the drawing, in the
  # LiveView's process (`AshDataTable.Kit.Words`, and for the rows of the
  # stream `AshDataTable.Item`, which turns a `Present.Row` into the item a
  # part is given, each cell with its text: ADR 0002). The messages the core
  # holds (a title, an error, a failed edit's message) are message terms,
  # passed on as they are.
  #
  # Nothing sensitive is in what this gives (F1). A row's record goes
  # through `AshDataTable.Sensitive.scrub/2` first, and a sensitive cell is
  # given as `:masked` with no value at all, not even the mask struct. A
  # sensitive field of the panel holds what was typed into it in this
  # panel, else nothing. The one way to a sensitive value is the reply to
  # `reveal`, which goes past this module to the hook alone.

  alias AshDataTable.Model
  alias AshDataTable.Resource.Embedding
  alias AshDataTable.Resource.Exposing
  alias AshDataTable.Sensitive

  defmodule Row do
    @moduledoc false
    # One row of the grid, as the stream holds it:
    #
    #   * `key` is the key in the row's DOM id, by which an event names the
    #     row (a claim when it comes back); `dom_id` the id of the item;
    #   * `rowindex` is 1-based, the header rows counted;
    #   * `names` what the hook names the row by where the key in its id
    #     does not, nil where it does;
    #   * `open?` whether the row is expanded; `current?`, in a table to
    #     choose from, whether it is the record chosen now;
    #   * `action_failure` the message of a row action that failed, else nil;
    #   * `cells` by column name, a `Present.Cell` each.
    defstruct [
      :key,
      :dom_id,
      :rowindex,
      names: nil,
      open?: false,
      current?: false,
      action_failure: nil,
      cells: %{}
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Cell do
    @moduledoc false
    # One cell of a row:
    #
    #   * `state` is `:value`, `:empty` (no value, or none loaded),
    #     `:masked` (a sensitive value that is there) or `:forbidden` (a
    #     field the person may not see on this record). A part draws from
    #     `state`, and from `value` where it is `:value`;
    #   * `value` is what `Model.Column.value/2` gives of the record as it
    #     is kept: a reference cell's label, a map cell's value with its
    #     sensitive fields masked. Nil but in the state `:value`;
    #   * `editable?` whether this person can edit this cell of this row;
    #   * `failure` of a cell whose save failed: what was typed (`""` for a
    #     sensitive cell, whatever was typed) and the action's message. Nil
    #     else, and nil on a cell that cannot be edited.
    defstruct value: nil, state: :value, editable?: false, failure: nil

    @type t :: %__MODULE__{}
  end

  defmodule Panel do
    @moduledoc false
    # The open action panel:
    #
    #   * `title`, `submit` (the text of its button) and `question` (asked
    #     before it runs, nil for none) as the core made them;
    #   * `kind` (`:cell`, `:row`, `:create`, `:table`, `:bulk`) and
    #     `destructive?`, whether its action destroys the record;
    #   * `errors` what the action said that is about none of the fields,
    #     nil for nothing;
    #   * `method` the HTTP method of its form, as `AshPhoenix.Form` says it;
    #   * `fields` one `Present.Field` per input;
    #   * `inside` what a field made of groups needs to know for the fields
    #     in it: the action's errors by place, the fields a person has been
    #     in (`touched`), whether "Run" was used, and the page's zone.
    defstruct [
      :title,
      :kind,
      :question,
      :submit,
      :method,
      destructive?: false,
      errors: nil,
      fields: [],
      inside: %{}
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Field do
    @moduledoc false
    # One field of the action panel:
    #
    #   * `name` the input's name, `path` the names it is sent under, and
    #     `form_name` the name of its control;
    #   * `input` the declaration of the field (`Model.Input`): type,
    #     editor, limits;
    #   * `value` what its control holds, as the control holds it; for a
    #     sensitive field what was typed into it in this panel, else `""`;
    #   * `errors` the errors that are shown at it, `places` the places of
    #     the values of an array they are about;
    #   * `chosen` for a field given by choosing records: by key as the
    #     field writes it, `%{label: {column, value, zone} | nil, row: …}`,
    #     whose label value the part formats; nil for a key of a record
    #     this person may not read;
    #   * `clear` for a sensitive field that can be emptied: `:offered`, or
    #     `:asked` once the person asked for it; nil else.
    defstruct [
      :name,
      :path,
      :form_name,
      :input,
      value: "",
      errors: [],
      places: [],
      chosen: nil,
      clear: nil
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Picker do
    @moduledoc false
    # The open picker: `title`, `question` and `error` as the core made them;
    # `several?` whether several records are chosen, `allow_none?` whether "None"
    # is offered; `current` the key the cell or field holds now, and
    # `chosen` the rows that are selected as it opens (`{key, names}`). The
    # table inside is of `destination`, read with `choose_action`, by
    # `destination_attribute`; `label` is what one of its records is
    # called, before it is translated. `name` the column or field.
    defstruct [
      :name,
      :title,
      :question,
      :error,
      :current,
      :destination,
      :choose_action,
      :destination_attribute,
      :label,
      several?: false,
      allow_none?: false,
      chosen: []
    ]

    @type t :: %__MODULE__{}
  end

  @doc """
  What is drawn in place of a sensitive value that is there: the same for
  every value. A `:masked` cell holds no value; this is what the part draws.
  """
  @spec mask() :: String.t()
  def mask, do: "••••••"

  @doc """
  A row of the page, for the stream. `record` is the record as it was read
  or returned; it is scrubbed here, and nothing of it but its cells' values
  is kept. `attributes`: `id` (the table's), `key`, `rowindex`, `names`,
  and optionally `failed` (the row's failed edits as the core keeps them),
  `open?` and `current?`.
  """
  @spec row(Model.t(), struct, map) :: Row.t()
  def row(%Model{} = model, record, attributes) do
    record = Sensitive.scrub(record, model.columns)
    failed = Map.get(attributes, :failed) || %{}
    cells = Map.get(failed, :cells, %{})

    %Row{
      key: attributes.key,
      dom_id: AshDataTable.Ids.row(attributes.id, attributes.key),
      rowindex: attributes.rowindex,
      names: attributes.names,
      open?: Map.get(attributes, :open?, false),
      current?: Map.get(attributes, :current?, false),
      action_failure: Map.get(failed, :action),
      cells: Map.new(model.columns, &{&1.name, cell(&1, record, cells[&1.name])})
    }
  end

  defp cell(column, record, failure) do
    value = Model.Column.value(column, record)
    editable? = editable?(column, value, record)
    {state, value} = state(column, value)

    %Cell{
      value: value,
      state: state,
      editable?: editable?,
      failure: if(editable? and not is_nil(failure), do: failure(column, failure))
    }
  end

  defp state(_column, %Ash.ForbiddenField{}), do: {:forbidden, nil}
  defp state(_column, nil), do: {:empty, nil}
  defp state(_column, %Ash.NotLoaded{}), do: {:empty, nil}

  # neither the value nor the mark that stands for it
  defp state(%{sensitive?: true}, value),
    do: if(Exposing.empty?(value), do: {:empty, nil}, else: {:masked, nil})

  defp state(_column, value), do: {:value, value}

  # What was typed into a sensitive cell is never given back.
  defp failure(%{sensitive?: true}, {_typed, message}), do: %{typed: "", message: message}

  defp failure(_column, {typed, message}), do: %{typed: typed, message: message}

  # Whether a person can edit this cell: its column is editable, and the
  # field is not hidden from them on this row. The field of a reference cell
  # is the foreign key an edit of it writes: the cell is edited where they
  # see the key, whatever they see of the record it points at.
  defp editable?(%{kind: :reference, editable?: true, reference: reference}, _value, record),
    do: not is_struct(Map.get(record, reference.source_attribute), Ash.ForbiddenField)

  defp editable?(_column, %Ash.ForbiddenField{}, _record), do: false

  # A map cell that holds something the person may not see (a field that a
  # field policy of the embedded resource hides) is not theirs to edit.
  defp editable?(%{editable?: true, cell_type: cell_type}, value, _record)
       when cell_type in [:map, {:array, :map}, :union],
       do: not Embedding.hidden?(value)

  defp editable?(column, _value, _record), do: column.editable?

  @doc """
  The open action panel (`AshDataTable.Panel`). `upload_errors` is what the
  live layer says of the file fields, by name: the texts shown at each.
  What each field shows is the panel's to say (`AshDataTable.Panel.field/3`).
  """
  @spec panel(AshDataTable.Panel.t(), map) :: Panel.t()
  def panel(%AshDataTable.Panel{} = panel, upload_errors \\ %{}) do
    %Panel{
      title: panel.title,
      kind: panel.kind,
      question: panel.question,
      submit: panel.submit,
      method: AshDataTable.Panel.method(panel),
      destructive?: AshDataTable.Panel.destructive?(panel),
      errors: panel.errors[nil],
      fields: Enum.map(panel.inputs, &field(panel, &1, upload_errors)),
      inside: %{
        errors: panel.errors,
        touched: panel.touched,
        submitted?: panel.submitted?,
        time_zone: panel.time_zone
      }
    }
  end

  defp field(panel, input, upload_errors) do
    shown = AshDataTable.Panel.field(panel, input, upload_errors)

    %Field{
      name: input.name,
      path: [Atom.to_string(input.name)],
      form_name: shown.form_name,
      input: input,
      value: shown.value,
      errors: shown.errors,
      places: shown.places,
      chosen: panel.chosen[input.name],
      clear: shown.clear
    }
  end

  @doc "The open picker."
  @spec picker(map) :: Picker.t()
  def picker(picker) do
    %Picker{
      name: picker.name,
      title: picker.title,
      question: picker.question,
      error: picker.error,
      current: picker.current,
      destination: picker.reference.destination,
      choose_action: picker.reference.choose_action,
      destination_attribute: picker.reference.destination_attribute,
      label: Model.label(picker.reference.destination),
      several?: picker.several?,
      allow_none?: picker.allow_none?,
      chosen: picker.chosen
    }
  end

  @doc """
  What a record is called, as a value: the first of the columns its table
  names a record by (`Model.naming/1`) that holds something this person may
  see on it, with the value it holds there. `blank?` says of a value whether
  it is nothing to call a record by. Nil when no column holds such a value.

  No column of a name is sensitive; a value made of fields may hold a
  sensitive field, which is masked here as in a row.
  """
  @spec label(Model.t(), struct, (Model.Column.t(), term -> boolean)) ::
          {Model.Column.t(), term} | nil
  def label(model, record, blank?) do
    record = Sensitive.scrub(record, model.columns)

    model
    |> Model.naming()
    |> Enum.find_value(fn column ->
      case Map.get(record, column.name) do
        %Ash.ForbiddenField{} -> nil
        %Ash.NotLoaded{} -> nil
        value -> if not blank?.(column, value), do: {column, value}
      end
    end)
  end
end
