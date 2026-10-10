defmodule AshTable.Model.Limits do
  @moduledoc false
  # What the constraints of an input's type say that its native control can
  # say too: the smallest and the largest number it takes, and the steps
  # between them. The table puts them on the control (`min`, `max`, `step`),
  # so that a person meets the limit before saving: the arrows of a number
  # input stop at it, and a screen reader reads it.
  #
  # They are a description and never a check: nothing in the browser refuses
  # a value because of them. What is typed is given to the action as it is,
  # and Ash says what is wrong with it.
  #
  # Only what a browser means exactly as Ash does is here:
  #
  #   * `min` and `max` of an integer, a float and a decimal, which include
  #     the bound itself in Ash and in HTML alike;
  #   * `step` is "1" for an integer, which takes whole numbers only, and
  #     "any" for a float and a decimal.
  #
  # Left out on purpose, as HTML has no attribute that means the same:
  #
  #   * `greater_than` and `less_than` of a float and a decimal, which
  #     exclude the bound: `min` and `max` would let the bound itself pass;
  #   * `max_length` and `min_length` of text: a browser counts UTF-16 code
  #     units of the text as it was typed, Ash counts codepoints, graphemes
  #     or bytes (`length_count`) of the text once it is trimmed. `maxlength`
  #     would stop a person from typing a value Ash takes, without a word;
  #   * `match` of text: the pattern is a regular expression of Erlang's,
  #     which a browser reads by other rules, and is matched after trimming;
  #   * `precision` and `scale` of a decimal, and how many values an array
  #     takes (`min_length`, `max_length`).
  #
  # The limits of an array are those of each of its values (`items`). A type
  # made of another (`Ash.Type.NewType`) has the limits of what it is made
  # of, with the constraints it gives it.

  @type t :: %{min: String.t() | nil, max: String.t() | nil, step: String.t() | nil}

  @none %{min: nil, max: nil, step: nil}

  @doc """
  The limits of an input, a field of a map cell, an argument or a column:
  anything that has a `type`, the Ash type with its constraints.
  """
  @spec of(%{:type => {Ash.Type.t() | nil, keyword}, optional(atom) => term}) :: t
  def of(%{type: {type, constraints}}), do: of(type, constraints)

  @doc "The limits of an Ash type with its constraints."
  @spec of(Ash.Type.t() | nil, keyword) :: t
  def of({:array, type}, constraints), do: of(type, constraints[:items] || [])
  def of(nil, _constraints), do: @none

  def of(type, constraints) do
    type = Ash.Type.get_type(type)

    cond do
      type == Ash.Type.Integer ->
        bounds(constraints, "1")

      type in [Ash.Type.Float, Ash.Type.Decimal] ->
        bounds(constraints, "any")

      is_atom(type) and Ash.Type.NewType.new_type?(type) ->
        of(type.subtype_of(), Ash.Type.NewType.constraints(type, constraints))

      true ->
        @none
    end
  end

  defp bounds(constraints, step) do
    %{min: number(constraints[:min]), max: number(constraints[:max]), step: step}
  end

  # A number as HTML writes one: digits, with a point where it has a
  # fraction. Anything else is no bound a control could have.
  defp number(number) when is_integer(number), do: Integer.to_string(number)
  defp number(number) when is_float(number), do: Float.to_string(number)

  defp number(%Decimal{coef: coef} = number) when is_integer(coef),
    do: Decimal.to_string(number, :normal)

  defp number(_none), do: nil
end
