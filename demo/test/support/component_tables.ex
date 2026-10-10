defmodule DemoWeb.Support.Cells.Probe do
  @moduledoc """
  A component that shows and edits, for the tests: it writes into the page
  what it was given, and refuses to render when it is given anything a
  component must never see: a value that is hidden from the person or not
  there, a record, or an assign beyond the documented ones.
  """
  use AshTable.Component

  @cell_assigns [:column, :text, :value]
  @editor_assigns [:column, :control, :label, :place, :value]

  def cell(assigns) do
    check!(assigns, @cell_assigns)

    ~H"""
    <span
      data-probe={@column.name}
      data-given={given(assigns)}
      data-value={inspect(@value)}
      data-column-label={@column.label}
      data-choices={@column.values && Enum.map_join(@column.values, ",", &elem(&1, 1))}
      phx-no-format
    >{@text}</span>
    """
  end

  def editor(assigns) do
    check!(assigns, @editor_assigns)

    ~H"""
    <span
      data-probe-editor={@column.name}
      data-given={given(assigns)}
      data-place={@place}
      data-label={@label}
      data-type={inspect(@column.type)}
      data-max={@column.constraints[:max]}
    >
      <input type="number" value={@value} {@control} />
    </span>
    """
  end

  # the names of the assigns the component was called with, besides what
  # Phoenix adds
  defp given(assigns) do
    assigns
    |> Map.keys()
    |> Enum.reject(&String.starts_with?(Atom.to_string(&1), "__"))
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp check!(assigns, documented) do
    given =
      for {name, _value} <- assigns, not String.starts_with?(Atom.to_string(name), "__"), do: name

    if Enum.sort(given) != documented do
      raise "the probe was given #{inspect(Enum.sort(given))}, and a component is given #{inspect(documented)}"
    end

    case assigns.value do
      %Ash.ForbiddenField{} -> raise "the probe was given a value that is hidden from the person"
      %Ash.NotLoaded{} -> raise "the probe was given a value that was not loaded"
      _value -> :ok
    end

    if Map.has_key?(assigns, :text) and is_nil(assigns.value) do
      raise "the probe was asked to show nothing"
    end

    for {name, %struct{}} <- assigns, Ash.Resource.Info.resource?(struct) do
      raise "the probe was handed a record as `#{name}`"
    end

    :ok
  end
end

defmodule DemoWeb.Support.Cells.Dial do
  @moduledoc "A component that only edits, and saves when its value changes."
  use AshTable.Component, commit: :change

  def editor(assigns) do
    ~H"""
    <span data-dial={@column.name}>
      <input type="range" min="0" max={@column.constraints[:max]} value={@value} {@control} />
      <span data-value-text aria-hidden="true">{@value}</span>
    </span>
    """
  end
end

defmodule Demo.Support.Styled do
  @moduledoc """
  A domain for the tests of what a table does with a column's `component`.
  Its resource exists for the tests only and keeps its records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Styled.Gauge
    resource Demo.Support.Styled.Portrait
  end
end

defmodule Demo.Support.Styled.Portrait do
  @moduledoc """
  A portrait: a text column that holds where a picture is, shown with
  `AshTable.Components.Image`.
  """
  use Ash.Resource,
    domain: Demo.Support.Styled,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  table do
    update_action :update

    column :name

    column :picture do
      component AshTable.Components.Image
    end
  end

  actions do
    defaults create: [:name, :picture], update: [:name, :picture]

    read :read do
      primary? true
      prepare build(sort: [name: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :picture, :string, public?: true
  end
end

defmodule Demo.Support.Styled.Gauge do
  @moduledoc """
  A gauge whose columns have components: `DemoWeb.Support.Cells.Probe`, which
  shows and edits and refuses what a component must never be given, and
  `DemoWeb.Support.Cells.Dial`, which only edits and saves on change.

  `code` is seen by an admin only, `amount` by an admin and by a gauge's
  owner. A viewer changes nothing. `level` is saved through an action of its
  own, which leaves a trace. `owner` is read-only in the table, though the
  table's action would accept it.
  """
  use Ash.Resource,
    domain: Demo.Support.Styled,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  field_policies do
    field_policy :code do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :amount do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(owner == ^actor(:name))
    end

    field_policy :* do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :name

    column :level do
      label "Rung"
      update_action :set_level
      component DemoWeb.Support.Cells.Probe
    end

    column :amount do
      component DemoWeb.Support.Cells.Probe
    end

    # "Status" in the demo's German, and "Done" is "Erledigt" there
    column :state do
      label "State"
      component DemoWeb.Support.Cells.Probe
    end

    column :volume do
      component DemoWeb.Support.Cells.Dial
    end

    column :code do
      component DemoWeb.Support.Cells.Probe
    end

    # `update` accepts it, and the table does not offer it: only the table
    # keeps it from being edited
    column :owner do
      update_action false
      component DemoWeb.Support.Cells.Probe
    end

    # opens the panel: attributes whose columns have an editor of their own,
    # one of them hidden from some people, one whose column has none, and an
    # argument
    action :tune

    create_action :create
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :level, :amount, :state, :volume, :code, :owner]
    end

    update :update do
      primary? true
      accept [:name, :amount, :state, :volume, :code, :owner]
      require_atomic? false
    end

    update :set_level do
      accept [:level]
      require_atomic? false
      change set_attribute(:trace, "set_level")
    end

    update :tune do
      accept [:level, :volume, :name, :amount]
      require_atomic? false
      argument :reason, :string
      change set_attribute(:trace, "tune")
    end
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if always()
    end

    policy action_type(:update) do
      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :level, :integer do
      public? true
      constraints min: 0, max: 10
    end

    attribute :amount, :integer, public?: true

    attribute :state, :atom do
      public? true
      constraints one_of: [:idle, :busy, :done]
    end

    attribute :volume, :integer do
      allow_nil? false
      default 5
      public? true
      constraints min: 0, max: 11
    end

    attribute :code, :string, public?: true
    attribute :owner, :string, public?: true
    # which action changed the record last: private, never a column
    attribute :trace, :string
  end
end
