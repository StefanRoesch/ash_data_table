defmodule DemoWeb.Locale do
  @moduledoc """
  Which language the demo's tables speak. The language switcher in the page
  header stores a locale in the session, and this module puts it into the
  process with `Gettext.put_locale/1`: for a request as a plug, for a
  LiveView as an `on_mount` hook.

  That is all a host does for `ash_table` to translate: the table looks its
  texts up in the locale of the process it runs in, in the backend named by
  `config :ash_table, gettext_backend: DemoWeb.Gettext`. Only the tables are
  translated here; the demo's own pages stay in English.
  """
  import Plug.Conn

  @session_key "locale"
  @locales [{"en", "English"}, {"de", "Deutsch"}]

  @doc "The locales the demo offers, each with its name."
  def locales, do: @locales

  @doc "The session key the chosen locale is stored under."
  def session_key, do: @session_key

  @doc "The locale of this process."
  def current, do: Gettext.get_locale(DemoWeb.Gettext)

  @doc "Plug: puts the session's locale into the process."
  def init(opts), do: opts

  def call(conn, _opts) do
    conn |> get_session(@session_key) |> put()
    conn
  end

  @doc "LiveView hook: puts the session's locale into the LiveView's process."
  def on_mount(:default, _params, session, socket) do
    put(session[@session_key])
    {:cont, socket}
  end

  @doc "Stores a locale in the session; one the demo does not offer is ignored."
  def put_locale(conn, locale) do
    if known?(locale), do: put_session(conn, @session_key, locale), else: conn
  end

  defp put(locale) do
    Gettext.put_locale(if(known?(locale), do: locale, else: "en"))
  end

  defp known?(locale), do: is_binary(locale) and List.keymember?(@locales, locale, 0)
end
