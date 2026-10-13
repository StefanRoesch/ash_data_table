defmodule AshTable.Resource.Referencing do
  @moduledoc false
  # What a reference cell needs: the label a resource's records are called
  # by, what a column that names a relationship shows of the related
  # record, and what a person chooses another related record with. Shared by
  # the verifiers (which report a mistake) and the table model (which builds
  # on the answer).
  #
  # Only the destination's own declarations are read here, never its table
  # model, as in `AshTable.Resource.Relating`.

  alias Ash.Resource.Info
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Resource.Relating

  @type label_reason ::
          {:label_not_found, atom}
          | {:label_not_public, atom}
          | {:label_sensitive, atom}
          | {:label_relationship, atom}
          | {:label_not_an_attribute, atom, :calculation | :aggregate}

  @type sticky_reason ::
          {:sticky_without_label, AshTable.Resource.Table.t()}
          | {:sticky_label_no_column, AshTable.Resource.Table.t(), atom}

  @type reason ::
          {:not_belongs_to, atom, atom}
          | {:no_table, atom, Ash.Resource.t()}
          | {:no_label_field, atom, Ash.Resource.t()}
          | {:unusable_label_field, atom, Ash.Resource.t(), label_reason}
          | {:no_read_action, atom, Ash.Resource.t()}
          | {:read_action_not_public, atom, Ash.Resource.t(), atom, :own | :primary}

  @typedoc """
  What a reference column shows: the `label` attribute of the record the
  `relationship` points at, read through `read_action` of the destination.
  """
  @type t :: %{
          relationship: struct,
          label: Ash.Resource.Attribute.t(),
          read_action: atom
        }

  @typedoc """
  What a person chooses the related record of a belongs-to relationship
  with: the picker, which shows the table of `destination` read through
  `read_action`, and gives the chosen record's `destination_attribute` as
  the value of `source_attribute`, the foreign key. `allow_nil?` says
  whether the key can be empty, which is when "none" can be chosen.
  """
  @type picking :: %{
          relationship: atom,
          destination: Ash.Resource.t(),
          source_attribute: atom,
          destination_attribute: atom,
          read_action: atom,
          allow_nil?: boolean
        }

  @typedoc """
  Why the related record of a relationship is not chosen in a picker. The
  first three are about the relationship, whatever is chosen for; the next
  three about the foreign key of a belongs-to that an action accepts; the
  last five about an argument that hands keys to a relationship
  (`AshTable.Resource.Managing`).
  """
  @type no_picker ::
          :filter
          | :no_table
          | :no_read_action
          | :key_not_found
          | :key_not_public
          | :key_not_writable
          | :not_public
          | :manual
          | :creates
          | :several_for_one
          | :related_read

  @typedoc """
  What a person chooses the records of a relationship with, where an
  argument of an action hands their keys to it: the picker, which shows the
  table of `destination` read through `read_action`, and gives the chosen
  records' `destination_attribute`. `several?` says whether any number of
  records is chosen, or one; `allow_nil?` whether the argument can be empty;
  and `related?` whether the argument is everything the relationship is to
  hold, so that its field starts with the records that are related now.

  The same for an argument whose resource the block names (`reference`,
  `declared/4`): there is no `relationship` then, the
  `destination_attribute` is the destination's primary key, and nothing is
  related already.
  """
  @type managing :: %{
          relationship: atom | nil,
          destination: Ash.Resource.t(),
          destination_attribute: atom,
          read_action: atom,
          several?: boolean,
          allow_nil?: boolean,
          related?: boolean
        }

  @relationships [
    Ash.Resource.Relationships.BelongsTo,
    Ash.Resource.Relationships.HasOne,
    Ash.Resource.Relationships.HasMany,
    Ash.Resource.Relationships.ManyToMany
  ]

  @doc "Whether what a column names is a relationship, and not a field."
  @spec relationship?(struct) :: boolean
  def relationship?(%struct{}), do: struct in @relationships

  @doc """
  The attribute a record of the resource is called by: the `label_field` of
  its `table` block. `:none` when the block names none.
  """
  @spec label_field(Ash.Resource.t() | Spark.Dsl.t()) ::
          {:ok, Ash.Resource.Attribute.t()} | :none | {:error, label_reason}
  def label_field(resource) do
    with {:ok, name} <- TableInfo.table_label_field(resource) do
      cond do
        attribute = Info.attribute(resource, name) ->
          cond do
            not attribute.public? -> {:error, {:label_not_public, name}}
            # what a record is called is shown wherever the record is named
            AshTable.Sensitive.sensitive?(attribute) -> {:error, {:label_sensitive, name}}
            true -> {:ok, attribute}
          end

        Info.relationship(resource, name) ->
          {:error, {:label_relationship, name}}

        Info.calculation(resource, name) ->
          {:error, {:label_not_an_attribute, name, :calculation}}

        Info.aggregate(resource, name) ->
          {:error, {:label_not_an_attribute, name, :aggregate}}

        true ->
          {:error, {:label_not_found, name}}
      end
    else
      :error -> :none
    end
  end

  @doc """
  What a column shows that names the relationship: the label of the related
  record. Only a belongs-to can be such a column, and only to a resource
  whose table says what its records are called by.

  The related record is read as Ash loads the relationship: through the
  relationship's own `read_action` when it declares one, else through the
  destination's primary read action. Either has to be `public?`: a table
  runs no private action, and the read action of the destination's table
  does not come into it.
  """
  @spec reference(struct) :: {:ok, t} | {:error, reason}
  def reference(%{name: name, destination: destination} = relationship) do
    cond do
      relationship.type != :belongs_to ->
        {:error, {:not_belongs_to, name, relationship.type}}

      not Relating.table?(destination) ->
        {:error, {:no_table, name, destination}}

      true ->
        with {:ok, label} <- label_of(name, destination),
             {:ok, read_action} <- read_action(relationship) do
          {:ok, %{relationship: relationship, label: label, read_action: read_action}}
        end
    end
  end

  defp label_of(name, destination) do
    case label_field(destination) do
      {:ok, label} -> {:ok, label}
      :none -> {:error, {:no_label_field, name, destination}}
      {:error, reason} -> {:error, {:unusable_label_field, name, destination, reason}}
    end
  end

  defp read_action(%{read_action: nil, name: name, destination: destination}) do
    case Info.primary_action(destination, :read) do
      nil ->
        {:error, {:no_read_action, name, destination}}

      %{public?: false} = action ->
        {:error, {:read_action_not_public, name, destination, action.name, :primary}}

      action ->
        {:ok, action.name}
    end
  end

  defp read_action(%{read_action: read_action, name: name, destination: destination}) do
    case Info.action(destination, read_action) do
      %{public?: false} ->
        {:error, {:read_action_not_public, name, destination, read_action, :own}}

      _public_or_ash_reports_it ->
        {:ok, read_action}
    end
  end

  @doc """
  What a person chooses the related record of a belongs-to relationship of
  `resource` with, or why there is nothing to choose it with.

  The records on offer are those of the destination's table: read through
  the relationship's own `read_action` when it declares one, which says
  which records it means and is the action Ash loads the related record
  through, else through the read action of the destination's table. Either
  has to be `public?`.

  There is no picker

    * where the destination has no table, as its table is what is shown;
    * where the relationship has a `filter`: which records it can then hold
      is for Ash's loader to say, with the record the relationship starts
      from, and a table cannot ask it for the candidates;
    * where the foreign key is no public, writable attribute: nothing from
      the outside sets it.
  """
  @spec picking(Ash.Resource.t() | Spark.Dsl.t(), struct) ::
          {:ok, picking} | {:error, no_picker}
  def picking(resource, %Ash.Resource.Relationships.BelongsTo{} = relationship) do
    %{destination: destination, source_attribute: source_attribute} = relationship

    with {:ok, read_action} <- choosing(relationship),
         {:ok, key} <- key(resource, source_attribute) do
      {:ok,
       %{
         relationship: relationship.name,
         destination: destination,
         source_attribute: source_attribute,
         destination_attribute: relationship.destination_attribute,
         read_action: read_action,
         allow_nil?: key.allow_nil?
       }}
    end
  end

  def picking(_resource, _relationship), do: {:error, :no_table}

  @doc """
  The read action the records of a relationship are chosen through, in a
  picker, or why there is no picker for it, whatever the choice is for: the
  first three reasons of `picking/2`.
  """
  @spec choosing(struct) :: {:ok, atom} | {:error, :filter | :no_table | :no_read_action}
  def choosing(%{destination: destination} = relationship) do
    with :ok <- unfiltered(relationship),
         :ok <- has_table(destination) do
      picker_read_action(relationship)
    end
  end

  @doc """
  What a person chooses the records with that an argument of an action
  hands to a relationship (`managed`: `AshTable.Resource.Managing`), or why
  there is nothing to choose them with.

  The records on offer are those of a picker for the relationship
  (`choosing/1`). Besides what keeps a relationship from having one, there
  is none

    * where the relationship is not public: a table shows nothing of a
      relationship the resource keeps to itself, and manual, which Ash
      does not manage;
    * where the change makes a record for a key that names none
      (`on_no_match: :create`, as `type: :direct_control` has it): a table
      chooses existing records, and a key that the action does not find
      among the related ones would become a new record;
    * where the argument holds a list of keys and the relationship one
      record: there is one to choose;
    * where the argument is everything the relationship is to hold, and
      the records that are related now could not be read without a private
      action. Its field starts with those records, read as Ash reads them
      when the action runs: through the relationship's own `read_action`,
      else the destination's primary read action, and for a many-to-many
      through the read action of the join resource before that. A table
      runs no private action, and a field that started without them would
      take them all away.
  """
  @spec managing(AshTable.Resource.Managing.t()) :: {:ok, managing} | {:error, no_picker}
  def managing(%{relationship: relationship} = managed) do
    with :ok <- public(relationship),
         :ok <- managed_by_ash(relationship),
         :ok <- existing(managed),
         :ok <- as_many(managed),
         {:ok, read_action} <- choosing(relationship),
         :ok <- related_read(managed) do
      {:ok,
       %{
         relationship: relationship.name,
         destination: relationship.destination,
         destination_attribute: managed.key,
         read_action: read_action,
         several?: managed.several?,
         allow_nil?: managed.allow_nil?,
         related?: managed.replaces?
       }}
    end
  end

  @typedoc """
  What is wrong with a `reference` of an `action` of the block: the action,
  the argument, and what keeps the argument from being chosen in a picker.
  """
  @type undeclarable ::
          {:reference_not_found, atom, atom, :attribute | nil}
          | {:reference_not_public, atom, atom}
          | {:reference_twice, atom, atom}
          | {:reference_record_argument, atom, atom}
          | {:reference_sensitive, atom, atom}
          | {:reference_managed, atom, atom, atom}
          | {:reference_no_table, atom, atom, module}
          | {:reference_no_read_action, atom, atom, module}
          | {:reference_no_single_key, atom, atom, module, [atom]}
          | {:reference_not_a_key, atom, atom, term, module, atom, term}

  @doc """
  What a person chooses the records with that an argument of an action
  names by their keys, where the block says which resource they are of
  (`reference`: `AshTable.Resource.Reference`), or what is wrong with the
  declaration.

  The records on offer are those of the destination's table, read through
  the read action behind it, which has to be `public?`. What the argument
  is given is the primary key of a chosen record, so the destination has
  to have one of one attribute, and the argument has to be stored as that
  attribute is, or be a list of such values: then any number is chosen.

  The argument has to be one a person gives at all: an argument of the
  action, `public?`, and not the one the table gives itself
  (`record_argument`). A sensitive one is not chosen: a picker shows what
  is chosen. And one that a `manage_relationship` change hands to a
  relationship needs no declaration and takes none: the relationship says
  which resource it is, and how the argument is read.
  """
  @spec declared(Ash.Resource.t() | Spark.Dsl.t(), struct, struct, atom | nil) ::
          {:ok, managing} | {:error, undeclarable}
  def declared(resource, action, %{name: name, destination: destination}, record_argument \\ nil) do
    at = action.name

    with {:ok, argument} <- referring_argument(resource, action, name),
         :ok <- not_given_by_table(at, name, record_argument),
         :ok <- not_managed(resource, action, name),
         :ok <- shown(at, argument),
         :ok <- declared_table(at, name, destination),
         {:ok, read_action} <- declared_read_action(at, name, destination),
         {:ok, key} <- single_key(at, name, destination),
         {:ok, several?} <- holds_key(at, argument, destination, key) do
      {:ok,
       %{
         relationship: nil,
         destination: destination,
         destination_attribute: key.name,
         read_action: read_action.name,
         several?: several?,
         allow_nil?: argument.allow_nil? != false,
         related?: false
       }}
    end
  end

  @doc """
  The first `reference` among those of an action that cannot be used
  (`declared/4`), or that names an argument another one names already.
  `:ok` when there is none.
  """
  @spec undeclarable(Ash.Resource.t() | Spark.Dsl.t(), struct, [struct], atom | nil) ::
          :ok | {:error, undeclarable}
  def undeclarable(resource, action, references, record_argument \\ nil) do
    names = Enum.map(references, & &1.name)

    Enum.find_value(references, :ok, fn reference ->
      cond do
        reference.name in (names -- Enum.uniq(names)) ->
          {:error, {:reference_twice, action.name, reference.name}}

        true ->
          with {:ok, _managing} <- declared(resource, action, reference, record_argument),
               do: nil
      end
    end)
  end

  defp referring_argument(resource, action, name) do
    case Enum.find(Map.get(action, :arguments) || [], &(&1.name == name)) do
      nil ->
        accepted? = name in (Map.get(action, :accept) || []) and Info.attribute(resource, name)
        {:error, {:reference_not_found, action.name, name, if(accepted?, do: :attribute)}}

      %{public?: false} ->
        {:error, {:reference_not_public, action.name, name}}

      argument ->
        {:ok, argument}
    end
  end

  defp not_given_by_table(action, name, name),
    do: {:error, {:reference_record_argument, action, name}}

  defp not_given_by_table(_action, _name, _record_argument), do: :ok

  defp not_managed(resource, action, name) do
    case AshTable.Resource.Managing.handed_to(resource, action, name) do
      nil -> :ok
      relationship -> {:error, {:reference_managed, action.name, name, relationship.name}}
    end
  end

  defp shown(action, argument) do
    if AshTable.Sensitive.sensitive?(argument),
      do: {:error, {:reference_sensitive, action, argument.name}},
      else: :ok
  end

  defp declared_table(action, name, destination) do
    if Relating.table?(destination),
      do: :ok,
      else: {:error, {:reference_no_table, action, name, destination}}
  end

  defp declared_read_action(action, name, destination) do
    # the picker shows the destination's default table
    case AshTable.Resource.Reading.read_action(
           destination,
           TableInfo.table!(destination, :default)
         ) do
      {:ok, read_action} ->
        {:ok, read_action}

      {:error, _private_or_none} ->
        {:error, {:reference_no_read_action, action, name, destination}}
    end
  end

  defp single_key(action, name, destination) do
    case Info.primary_key(destination) do
      [key] -> {:ok, Info.attribute(destination, key)}
      keys -> {:error, {:reference_no_single_key, action, name, destination, keys}}
    end
  end

  # Whether the argument holds one key, or a list of them: it is stored as
  # the key is.
  defp holds_key(action, %{type: type} = argument, destination, key) do
    constraints = argument.constraints || []
    stored = Ash.Type.storage_type(key.type, key.constraints || [])

    {several?, of, with} =
      case type do
        {:array, item} -> {true, item, constraints[:items] || []}
        one -> {false, one, constraints}
      end

    if Ash.Type.storage_type(of, with) == stored,
      do: {:ok, several?},
      else:
        {:error,
         {:reference_not_a_key, action, argument.name, type, destination, key.name, key.type}}
  end

  defp public(%{public?: true}), do: :ok
  defp public(_relationship), do: {:error, :not_public}

  defp managed_by_ash(relationship),
    do: if(Relating.manual?(relationship), do: {:error, :manual}, else: :ok)

  defp existing(%{creates?: true}), do: {:error, :creates}
  defp existing(_managed), do: :ok

  defp as_many(%{several?: true, relationship: %{cardinality: :one}}),
    do: {:error, :several_for_one}

  defp as_many(_managed), do: :ok

  # The records that are related now are read as Ash loads the relationship.
  defp related_read(%{replaces?: false}), do: :ok

  defp related_read(%{relationship: relationship}) do
    with {:ok, _read_action} <- read_action(relationship),
         true <- Enum.all?(Relating.passed(relationship), &public_or_none?/1) do
      :ok
    else
      _private_or_none -> {:error, :related_read}
    end
  end

  defp public_or_none?(%{action: %{public?: false}}), do: false
  defp public_or_none?(_passed), do: true

  defp unfiltered(%{filter: nil}), do: :ok
  defp unfiltered(_relationship), do: {:error, :filter}

  defp has_table(destination),
    do: if(Relating.table?(destination), do: :ok, else: {:error, :no_table})

  # As a nested table of the relationship reads that shows the destination's
  # default table, which is the one in the picker: `Relating.read_action/2`.
  defp picker_read_action(relationship) do
    case Relating.read_action(relationship, :default) do
      {:ok, action} -> {:ok, action.name}
      {:error, _private_or_none} -> {:error, :no_read_action}
    end
  end

  defp key(resource, name) do
    case Info.attribute(resource, name) do
      nil -> {:error, :key_not_found}
      %{public?: false} -> {:error, :key_not_public}
      %{writable?: false} -> {:error, :key_not_writable}
      attribute -> {:ok, attribute}
    end
  end

  @doc "Why a relationship's related record is never chosen in a picker, for a diagnostic."
  @spec no_picker(struct, no_picker) :: String.t()
  def no_picker(relationship, :filter),
    do:
      "The relationship `#{relationship.name}` has a `filter`, so a table cannot say which records it can hold, and offers none to choose from."

  def no_picker(relationship, :no_table),
    do:
      "The destination of `#{relationship.name}`, #{inspect(relationship.destination)}, has no table to choose a record from."

  def no_picker(relationship, :no_read_action),
    do:
      "The records to choose from would be read through an action of #{inspect(relationship.destination)} that is not a public read action: the relationship's own `read_action`, or the one behind the destination's table. " <>
        AshTable.Resource.Reading.private_action()

  def no_picker(relationship, :key_not_found),
    do:
      "The resource has no attribute `#{relationship.source_attribute}`, the foreign key of `#{relationship.name}`."

  def no_picker(relationship, :key_not_public),
    do:
      "`#{relationship.source_attribute}`, the foreign key of `#{relationship.name}`, is not public (`attribute_public? false`). Only a `public?` attribute is set through a table."

  def no_picker(relationship, :key_not_writable),
    do:
      "`#{relationship.source_attribute}`, the foreign key of `#{relationship.name}`, is declared `attribute_writable? false`, so no action can set it."

  def no_picker(relationship, :not_public),
    do:
      "The relationship `#{relationship.name}` is not public. A table shows nothing of a relationship the resource keeps to itself."

  def no_picker(relationship, :manual),
    do: "The relationship `#{relationship.name}` is manual, and Ash does not manage one."

  def no_picker(relationship, :creates),
    do:
      "The change makes a record of `#{relationship.name}` for a key that names none (`on_no_match: :create`, as `type: :direct_control` has it). A table chooses existing records, and creates none through an argument."

  def no_picker(relationship, :several_for_one),
    do:
      "The argument holds a list of keys, and `#{relationship.name}` holds one record: there is one to choose, not several."

  def no_picker(relationship, :related_read),
    do:
      "The argument is everything `#{relationship.name}` is to hold, so its field starts with the records that are related now, and those would be read through an action that is not a public read action: the relationship's own `read_action` or the primary read action of #{inspect(relationship.destination)}, or for a many-to-many that of the join resource. " <>
        AshTable.Resource.Reading.private_action()

  @doc "What is wrong with a `reference` of an action, for a diagnostic."
  @spec undeclarable_message(undeclarable) :: String.t()
  def undeclarable_message({:reference_not_found, action, name, :attribute}),
    do:
      "The action `#{action}` says `reference :#{name}`, and `#{name}` is an attribute the action " <>
        "accepts, not one of its arguments. A `reference` is for an argument. The foreign key of a " <>
        "public belongs-to relationship is chosen in the picker without one: the relationship says " <>
        "which resource it points at."

  def undeclarable_message({:reference_not_found, action, name, nil}),
    do: "The action `#{action}` says `reference :#{name}`, and has no argument named `#{name}`."

  def undeclarable_message({:reference_not_public, action, name}),
    do:
      "The action `#{action}` says `reference :#{name}`, and its argument `#{name}` is not public. " <>
        "A private argument is not given from the outside, and a table is the outside."

  def undeclarable_message({:reference_twice, action, name}),
    do:
      "The action `#{action}` has more than one `reference :#{name}`. An argument refers to one resource."

  def undeclarable_message({:reference_record_argument, action, name}),
    do:
      "The action `#{action}` says `reference :#{name}`, and `#{name}` is its `record_argument`: " <>
        "the table gives it the key of the row, and nobody chooses it. Leave the `reference` out."

  def undeclarable_message({:reference_sensitive, action, name}),
    do:
      "The action `#{action}` says `reference :#{name}`, and its argument `#{name}` is declared " <>
        "`sensitive?: true`. A picker shows what is chosen, and a table shows nothing of a sensitive " <>
        "input: it has no field for this one."

  def undeclarable_message({:reference_managed, action, name, relationship}),
    do:
      "The action `#{action}` says `reference :#{name}`, and a `manage_relationship` change of the " <>
        "action hands `#{name}` to the relationship `#{relationship}`. The relationship says which " <>
        "resource the argument refers to, and the change how it is read. Leave the `reference` out."

  def undeclarable_message({:reference_no_table, action, name, destination}),
    do:
      "The action `#{action}` says `reference :#{name}, #{inspect(destination)}`, and " <>
        "#{inspect(destination)} has no table: it is no resource that lists `AshTable.Resource` in " <>
        "its extensions. The records of a reference are chosen from the table of their resource."

  def undeclarable_message({:reference_no_read_action, action, name, destination}),
    do:
      "The action `#{action}` says `reference :#{name}, #{inspect(destination)}`, and the table of " <>
        "#{inspect(destination)} has no public read action to read the records to choose from: " <>
        "the `read_action` of its `table` block, else its primary read action. " <>
        AshTable.Resource.Reading.private_action()

  def undeclarable_message({:reference_no_single_key, action, name, destination, []}),
    do:
      "The action `#{action}` says `reference :#{name}, #{inspect(destination)}`, and " <>
        "#{inspect(destination)} has no primary key: there is nothing of a chosen record to give the argument."

  def undeclarable_message({:reference_no_single_key, action, name, destination, keys}),
    do:
      "The action `#{action}` says `reference :#{name}, #{inspect(destination)}`, and the primary " <>
        "key of #{inspect(destination)} is #{Enum.map_join(keys, ", ", &"`#{&1}`")}: several " <>
        "attributes. One argument holds the primary key of a record only where that is one attribute."

  def undeclarable_message(
        {:reference_not_a_key, action, name, type, destination, key, key_type}
      ),
      do:
        "The action `#{action}` says `reference :#{name}, #{inspect(destination)}`, and the argument " <>
          "is of the type #{inspect(type)}, which is not stored as the primary key `#{key}` of " <>
          "#{inspect(destination)} is (#{inspect(key_type)}), nor a list of it. The argument is given " <>
          "the primary key of the chosen record as it is."

  @doc """
  Whether a table that says `sticky_label? true` has a label column to keep
  in view: the resource names a `label_field`, and the table shows it, as a
  column of its own or with the default set. A `label_field` that cannot be
  used is reported for itself (`label_field/1`), and not here.
  """
  @spec sticky_label(Ash.Resource.t() | Spark.Dsl.t(), AshTable.Resource.Table.t()) ::
          :ok | {:error, sticky_reason}
  def sticky_label(_resource, %{sticky_label?: false}), do: :ok

  def sticky_label(resource, %{columns: columns} = table) do
    case label_field(resource) do
      :none ->
        {:error, {:sticky_without_label, table}}

      {:ok, %{name: name}} ->
        if columns == [] or Enum.any?(columns, &(&1.name == name)),
          do: :ok,
          else: {:error, {:sticky_label_no_column, table, name}}

      {:error, _reported_for_itself} ->
        :ok
    end
  end

  @doc "What is wrong with a `label_field`, with `sticky_label?`, or with a column that names a relationship, for a diagnostic."
  @spec message(label_reason | sticky_reason | reason) :: String.t()
  def message({:sticky_without_label, table}),
    do:
      "#{sentence(AshTable.Resource.Table.in_words(table))} says `sticky_label? true`, and the resource declares no `label_field`. " <>
        "`sticky_label?` keeps the label column in view while the table scrolls sideways: " <>
        "add `label_field` to the `table` block of the resource, or take `sticky_label?` out."

  def message({:sticky_label_no_column, table, name}),
    do:
      "#{sentence(AshTable.Resource.Table.in_words(table))} says `sticky_label? true` and has no column of the label, `#{name}`. " <>
        "`sticky_label?` keeps the label column in view while the table scrolls sideways: " <>
        "add `column :#{name}`, or take `sticky_label?` out."

  def message({:label_not_found, name}), do: "The resource has no attribute named `#{name}`."

  def message({:label_not_public, name}),
    do: "`#{name}` is not public. Only a `public?` attribute can be the label of a record."

  def message({:label_sensitive, name}),
    do:
      "`#{name}` is declared `sensitive?: true`. The label of a record is shown wherever a table names the record: in a reference cell, in the picker, in the heading of the action panel. A table shows a sensitive value to nobody who has not asked for it, so it cannot be the label: name another attribute."

  def message({:label_relationship, name}),
    do:
      "`#{name}` is a relationship. The label of a record is one of its own attributes: name an attribute of this resource."

  def message({:label_not_an_attribute, name, kind}),
    do:
      "`#{name}` is #{kind(kind)}. The label of a record has to be an attribute: it is read with the record's key and nothing else."

  def message({:not_belongs_to, name, type}),
    do:
      "`#{name}` is #{kind(type)} relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :#{name}`."

  def message({:no_table, name, destination}),
    do:
      "The destination of `#{name}`, #{inspect(destination)}, has no table: it does not list `AshTable.Resource` in its extensions. A column that names a relationship shows the related record's label, which the destination's table declares with `label_field`."

  def message({:no_label_field, name, destination}),
    do:
      "The destination of `#{name}`, #{inspect(destination)}, declares no `label_field`. A column that names a relationship shows the related record's label: add `label_field` to the `table` block of #{inspect(destination)}."

  def message({:unusable_label_field, name, destination, reason}),
    do:
      "The `label_field` of #{inspect(destination)}, the destination of `#{name}`, cannot be used. " <>
        message(reason)

  def message({:no_read_action, name, destination}),
    do:
      "The destination of `#{name}`, #{inspect(destination)}, has no primary read action, and the relationship names no `read_action`. The related record of a column is read as Ash loads the relationship, which needs one of the two."

  def message({:read_action_not_public, name, destination, action, whose}) do
    whose =
      case whose do
        :own -> "the relationship's own `read_action`"
        :primary -> "its primary read action"
      end

    "`#{name}` points to #{inspect(destination)}, whose read action `#{action}`, #{whose}, is not public. " <>
      "The related record of a column is read as Ash loads the relationship. " <>
      AshTable.Resource.Reading.private_action() <>
      " Make `#{action}` public, give the relationship a public `read_action`, or do not show `#{name}` as a column."
  end

  defp kind(:calculation), do: "a calculation"
  defp kind(:aggregate), do: "an aggregate"
  defp kind(:has_many), do: "a has-many"
  defp kind(:has_one), do: "a has-one"
  defp kind(:many_to_many), do: "a many-to-many"
  defp kind(type), do: "a #{type}"

  defp sentence(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
end
