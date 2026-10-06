defmodule AshTable.Gettext do
  @moduledoc """
  The Gettext backend the table's own texts come from, unless the host names
  one of its own.

  Every text a table shows that is the table's ("No records", "Clear
  filters", "1 result", …) is a message of the Gettext domain `ash_table`. The
  messages are written in English, and this backend holds no translation, so
  out of the box a table speaks English.

  ## Translating the table

  Name the host's backend:

      config :ash_table, gettext_backend: MyAppWeb.Gettext

  and give it the domain, one file per locale: copy this package's template,
  `deps/ash_table/priv/gettext/ash_table.pot`, to the host's
  `priv/gettext/LOCALE/LC_MESSAGES/ash_table.po` and fill in each `msgstr`. A
  message without a translation is shown in English. (Copy it as the `.po`
  file, not as a template of the host's: `mix gettext.extract` removes from a
  host's templates the messages it does not find in the host's own code.)

  The table translates in the locale of the process it runs in: what the
  host's plug and `on_mount` hook set with `Gettext.put_locale/1`.

  The same domain is where a host translates what the table shows of its
  resources' own wording: the labels of columns (declared, or the humanised
  field names), the labels of enum values, the questions of `confirm`, and the
  names of the tables. Each is looked up as a message, and shown as it is
  when the domain has no entry for it:

      msgid "Due on"
      msgstr "Fällig am"

  The messages of the resources' actions are another matter: see
  `:translate_error` in the configuration of `AshTable`.
  """
  use Gettext.Backend, otp_app: :ash_table
end
