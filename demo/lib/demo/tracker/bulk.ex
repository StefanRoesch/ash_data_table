defmodule Demo.Tracker.Bulk do
  @moduledoc """
  The options of a bulk action that a generic action of the tracker runs:
  as the person who runs it, in their organization
  (`Ash.Context.to_opts/1`). A record a policy refuses fails the whole
  action, as it would one record at a time; each record is announced, so
  tables that follow live updates see it; and the records come back, so the
  action can say how many.
  """

  @doc "For `Ash.bulk_create!/4`."
  @spec creating(Ash.Resource.Actions.Implementation.Context.t()) :: keyword
  def creating(context) do
    Ash.Context.to_opts(context) ++
      [
        authorize_changeset_with: :error,
        notify?: true,
        return_records?: true,
        return_errors?: true,
        stop_on_error?: true
      ]
  end

  @doc "For `Ash.bulk_update!/4` and `Ash.bulk_destroy!/4`: atomic where it can be."
  @spec changing(Ash.Resource.Actions.Implementation.Context.t()) :: keyword
  def changing(context),
    do: [strategy: [:atomic, :atomic_batches, :stream]] ++ creating(context)
end
