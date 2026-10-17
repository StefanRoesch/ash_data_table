defmodule AshDataTable.Text do
  @moduledoc false
  # The one place where a table's texts become what a person reads. Three
  # kinds of text pass through here:
  #
  #   * the table's own (`t/2`, `n/2`): messages of the Gettext domain
  #     `ash_data_table`, written in English, looked up in the backend the host
  #     names with `config :ash_data_table, gettext_backend: …`, else in
  #     `AshDataTable.Gettext`, which has no translations;
  #
  #   * the resource's wording that the table shows (`label/1`): column
  #     labels, enum labels, questions. They are looked up in the same domain
  #     of the same backend, and come back as they are when it has no entry;
  #
  #   * the messages of the resource's actions (`error/1`): given to the
  #     function the host names with `config :ash_data_table, translate_error: …`,
  #     which is the `translate_error/1` of a Phoenix app's core components;
  #     without one, the message with its variables filled in.
  #
  # Both settings are read when a text is needed, as the layout is, so that a
  # host changes them without compiling this library again.
  #
  # The data layer makes no words: it says what it has to say as a message
  # (`t:message/0`), and the drawing and the live layer's replies turn it into
  # text with `say/1`, in the LiveView's process, whose locale it is.

  @domain "ash_data_table"

  # the keys are the public list's (`AshDataTable.Messages`); a key that is
  # not in it is refused, so that the list says every text a table shows
  @type key :: AshDataTable.Messages.key()

  @typedoc """
  A message, as the table's code passes it on until it is said: one of the
  data layer's (`t:AshDataTable.Errors.message/0`), or a text that is words
  already: a label of the model, which the live layer translates once as
  it builds the model for a person.
  """
  @type message :: AshDataTable.Errors.message() | String.t()

  @doc "What a message says, in the locale of the process that asks."
  @spec say(message) :: String.t()
  def say({:text, key, bindings}) do
    case AshDataTable.Messages.all() do
      # a key with a form per number has `count` among its bindings
      %{^key => %{msgid_plural: plural}} when is_binary(plural) ->
        {count, bindings} = Keyword.pop!(bindings, :count)
        n(key, count, said(bindings))

      _one_form ->
        t(key, said(bindings))
    end
  end

  def say({:ash, message, vars}), do: error({message, vars})
  def say({:label, text}), do: label(text)
  def say({:join, separator, messages}), do: Enum.map_join(messages, separator, &say/1)

  def say({:once, separator, messages}),
    do: messages |> once() |> Enum.map_join(separator, &say/1)

  def say(text) when is_binary(text), do: text

  @doc """
  Messages each once by what they say: one whose words another before it
  says already is left out, as a text that is shown twice would be.
  """
  @spec once([message]) :: [message]
  def once(messages), do: Enum.uniq_by(messages, &say/1)

  @doc """
  Messages with how many times each came up (what a run on a selection
  counts), each once by what it says: the counts of those that say the
  same are added up, in the place of the first.
  """
  @spec counted([{message, pos_integer}]) :: [{message, pos_integer}]
  def counted(counts) do
    counts
    |> Enum.reduce([], fn {message, count}, counted ->
      words = say(message)

      case Enum.find_index(counted, fn {known, _count, _message} -> known == words end) do
        nil ->
          [{words, count, message} | counted]

        at ->
          List.update_at(counted, at, fn {known, before, first} ->
            {known, before + count, first}
          end)
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {_words, count, message} -> {message, count} end)
  end

  defp said(bindings) do
    for {name, value} <- bindings, do: {name, if(message?(value), do: say(value), else: value)}
  end

  defp message?({:text, key, bindings}) when is_atom(key) and is_list(bindings), do: true
  defp message?({:ash, message, _vars}) when is_binary(message), do: true
  defp message?({:label, text}) when is_binary(text), do: true

  defp message?({joined, separator, messages})
       when joined in [:join, :once] and is_binary(separator) and is_list(messages),
       do: true

  defp message?(_value), do: false

  @doc "The text for `key`, with `%{name}` placeholders filled from `bindings`."
  @spec t(key, keyword) :: String.t()
  def t(key, bindings \\ []) do
    %{msgid: msgid} = known!(key)
    Gettext.dgettext(backend(), @domain, msgid, Map.new(bindings))
  end

  @doc """
  The text for `key` in the plural form of `count`, which is bound as
  `%{count}`, with the other placeholders filled from `bindings`.
  """
  @spec n(key, non_neg_integer, keyword) :: String.t()
  def n(key, count, bindings \\ []) do
    %{msgid: singular, msgid_plural: plural} = known!(key)
    Gettext.dngettext(backend(), @domain, singular, plural, count, Map.new(bindings))
  end

  defp known!(key) do
    case AshDataTable.Messages.all() do
      %{^key => %{msgid: msgid} = known} when is_binary(msgid) ->
        known

      _unknown ->
        raise ArgumentError,
              "#{inspect(key)} is no key of AshDataTable.Messages: a text a table shows is in its list"
    end
  end

  @doc "The locale the table's texts are said in, in this process: Gettext's, of its backend."
  @spec locale() :: String.t()
  def locale, do: Gettext.get_locale(backend())

  @doc """
  A text of the resource's as the table shows it: translated when the
  `ash_data_table` domain of the host's backend has it as a message, else as it is.
  """
  @spec label(String.t()) :: String.t()
  def label(""), do: ""
  def label(text) when is_binary(text), do: Gettext.dgettext(backend(), @domain, text)

  # A message of an action, with its variables: through the host's error
  # translator when one is configured, else with the variables filled in.
  defp error({message, vars}) when is_binary(message) do
    vars = vars(vars)

    case Application.get_env(:ash_data_table, :translate_error) do
      nil ->
        Enum.reduce(vars, message, fn {name, value}, message ->
          String.replace(message, "%{#{name}}", to_string(value))
        end)

      {module, function} when is_atom(module) and is_atom(function) ->
        to_string(apply(module, function, [{message, vars}]))
    end
  end

  # The variables of an error as the bindings of a message: by name, with
  # values that can be written out. Numbers stay numbers, for plural forms.
  defp vars(vars) do
    for {name, value} <- List.wrap(if(is_map(vars), do: Map.to_list(vars), else: vars)),
        is_atom(name) or is_binary(name) do
      {name, var(value)}
    end
  end

  defp var(value) when is_binary(value) or is_number(value), do: value
  defp var(value) when is_atom(value), do: to_string(value)
  defp var(value), do: inspect(value)

  defp backend, do: Application.get_env(:ash_data_table, :gettext_backend, AshDataTable.Gettext)
end
