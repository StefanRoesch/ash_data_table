defmodule AshDataTable.Model.Access do
  @moduledoc false
  # What Ash says a person may see and do, asked before any record is read.
  # The table adds no rule of its own: both questions go to Ash's own checks,
  # the ones a host application asks to shape a page (`Ash.can_see_fields/4`
  # and `Ash.can/3`). Neither reads a record or runs a query.

  @typedoc "Who is asking: the options of `AshDataTable.Query.read/3` that say so."
  @type reader :: keyword

  @doc """
  The fields among `fields` that the person can never see through the read
  action: on no record, whatever it holds.

  A field whose visibility depends on the record is not among them: the
  person may see it on some records, and Ash hides it on the others when they
  are read.

  A question Ash cannot answer counts as "never": the field is left out
  rather than shown by mistake.
  """
  @spec hidden_fields(Ash.Resource.t(), atom, [atom], reader) :: [atom]
  def hidden_fields(_resource, _read_action, [], _reader), do: []

  def hidden_fields(resource, read_action, fields, reader) do
    ensure_authorizers_loaded(resource)
    {actor, opts} = actor_and_opts(reader)

    # `filter_is: true`, the default, is what tells the two kinds of hidden
    # field apart: a field behind a check on the record counts as visible.
    case Ash.can_see_fields({resource, read_action}, actor, fields, opts) do
      {:ok, visible} -> Enum.reject(fields, &Map.get(visible, &1, false))
      {:error, _error} -> fields
    end
  end

  @doc """
  The fields among `fields` that the person sees through the read action on
  some records and not on others: those behind a field policy that looks at
  the record. `fields` are fields the person does not never see.

  A question Ash cannot answer counts as "on some records only".
  """
  @spec partly_hidden_fields(Ash.Resource.t(), atom, [atom], reader) :: [atom]
  def partly_hidden_fields(_resource, _read_action, [], _reader), do: []

  def partly_hidden_fields(resource, read_action, fields, reader) do
    ensure_authorizers_loaded(resource)
    {actor, opts} = actor_and_opts(reader)

    # With `filter_is: false` a field behind a check on the record counts as
    # hidden: what is left as visible is seen on every record.
    case Ash.can_see_fields({resource, read_action}, actor, fields, [filter_is: false] ++ opts) do
      {:ok, always} -> Enum.reject(fields, &Map.get(always, &1, false))
      {:error, _error} -> fields
    end
  end

  @doc """
  The actions among `actions` that the person can never run: on no record,
  whatever it holds. Asked of the update actions behind a table's columns,
  and of the read action behind a nested table.

  An action the person may run on some records only is not among them:
  whether it runs on one record is the action's to say when it is run.

  A generic action is asked about without its arguments: a check that looks
  at one answers for none.

  A question Ash cannot answer counts as "never". Ash raises for one about
  a generic action whose policy holds a check on a record (ash 3.34.4:
  "Cannot use filter or runtime checks with generic actions"), which such
  an action has none of; it would raise the same when the action is run.
  """
  @spec forbidden_actions(Ash.Resource.t(), [atom], reader) :: [atom]
  def forbidden_actions(resource, actions, reader) do
    ensure_authorizers_loaded(resource)
    {actor, opts} = actor_and_opts(reader)

    Enum.filter(actions, fn action ->
      # Asked about the action as such, with no record to look at
      # (`pre_flight?: false`): a check on the record then has no answer and
      # Ash says `:maybe`, where a pre-flight check would try it on an empty
      # record and say no. `run_queries?: false` keeps it to what is known
      # without the database.
      case can(resource, action, actor, opts) do
        {:ok, true} -> false
        {:ok, :maybe} -> false
        _never_or_unknown -> true
      end
    end)
  end

  defp can(resource, action, actor, opts) do
    opts = [pre_flight?: false, run_queries?: false, maybe_is: :maybe] ++ opts

    case Ash.Resource.Info.action(resource, action) do
      %{type: :action} ->
        try do
          Ash.can({resource, action}, actor, opts)
        rescue
          _unanswerable -> :error
        end

      _action_on_records ->
        Ash.can({resource, action}, actor, opts)
    end
  end

  # `Ash.can_see_fields/4` asks each authorizer of the resource only if its
  # module is already loaded (ash 3.34.4: `Ash.Authorizer` tests
  # `function_exported?/3` without loading it), and takes a module that is not
  # as "every field is visible". Outside a release modules are loaded on first
  # use, so a table opened before anything else has run a policy would show
  # every column. Internal ticket #28: this goes when Ash loads the module
  # before it asks.
  defp ensure_authorizers_loaded(resource) do
    resource |> Ash.Resource.Info.authorizers() |> Enum.each(&Code.ensure_loaded/1)
  end

  # Ash's checks take the actor as an argument of its own, and the tenant
  # among the options. With a scope the actor is the scope's; the scope goes
  # along for its tenant and context.
  defp actor_and_opts(reader) do
    case reader[:scope] do
      nil ->
        {reader[:actor], reader |> Keyword.take([:tenant]) |> reject_nil()}

      scope ->
        {Keyword.get(Ash.Scope.to_opts(scope), :actor), [scope: scope]}
    end
  end

  defp reject_nil(opts), do: Enum.reject(opts, fn {_key, value} -> is_nil(value) end)
end
