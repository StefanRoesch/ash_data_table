defmodule Demo.Actors do
  @moduledoc """
  The five fixed actors of the demo, and how an actor is found.

  Four are users with stable ids, created by the seed; the fifth is nobody
  (`nil`). The actor switcher stores a user id in the session under
  `session_key/0`; no id means nobody is logged in.
  """

  alias Demo.Tracker.User

  @session_key "actor_id"

  @organizations %{
    acme: %{id: "0a000000-0000-4000-8000-000000000001", name: "Acme", slug: "acme"},
    globex: %{id: "0a000000-0000-4000-8000-000000000002", name: "Globex", slug: "globex"}
  }

  @users [
    %{
      key: :admin,
      id: "0b000000-0000-4000-8000-000000000001",
      name: "Ada Admin",
      email: "admin@acme.test",
      role: :admin,
      organization: :acme
    },
    %{
      key: :member,
      id: "0b000000-0000-4000-8000-000000000002",
      name: "Max Member",
      email: "member@acme.test",
      role: :member,
      organization: :acme
    },
    %{
      key: :viewer,
      id: "0b000000-0000-4000-8000-000000000003",
      name: "Vera Viewer",
      email: "viewer@acme.test",
      role: :viewer,
      organization: :acme
    },
    %{
      key: :outsider,
      id: "0b000000-0000-4000-8000-000000000004",
      name: "Olga Outsider",
      email: "outsider@globex.test",
      role: :member,
      organization: :globex
    }
  ]

  @doc "The session key the actor switcher writes the chosen user id to."
  def session_key, do: @session_key

  @doc "The four fixed users. The fifth actor, nobody, is the absence of one."
  def users, do: @users

  @doc "The keys of all five actors."
  def keys, do: Enum.map(@users, & &1.key) ++ [:nobody]

  @doc "The fixed user with the given key, or `nil` for `:nobody`."
  def user(:nobody), do: nil
  def user(key), do: Enum.find(@users, &(&1.key == key)) || raise("unknown actor #{inspect(key)}")

  @doc "The fixed id of the user with the given key."
  def id(key), do: user(key).id

  @doc "The two fixed organizations, by key (`:acme`, `:globex`)."
  def organizations, do: @organizations

  def organization(key), do: Map.fetch!(@organizations, key)
  def organization_id(key), do: organization(key).id

  @doc """
  Loads the user a session's actor id points to. Returns `nil` for no id, an
  id that is not a UUID, or an id of no user: all of them mean nobody.
  """
  def fetch(id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, %User{} = user} <- Ash.get(User, uuid, authorize?: false, not_found_error?: false) do
      user
    else
      _ -> nil
    end
  end

  def fetch(_), do: nil

  @doc "The tenant that goes with an actor: their organization's id."
  def tenant(%User{organization_id: organization_id}), do: organization_id
  def tenant(nil), do: nil
end
