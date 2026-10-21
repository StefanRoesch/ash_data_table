defmodule AshDataTable.Kit.Projection.Pagination do
  @moduledoc false
  # The projection of the `pagination` part (`AshDataTable.Kit.Projection`),
  # under a table on the page and in a nested table's footer: the range,
  # Previous, the page numbers offered, Next and "Rows per page". Each key
  # of its own inputs (`key/2`).

  alias AshDataTable.Attrs
  alias AshDataTable.Kit.Projection.Said
  alias AshDataTable.Model

  @doc false
  # Whether there are pages to go through.
  def pages?(page, model), do: not is_nil(page) and model.pagination.strategy != :none

  @doc false
  def keys,
    do: [:nested?, :element, :range, :previous, :next, :pages, :sizes, :texts, :messages]

  @doc false
  def key(:nested?, %{nested?: nested?}), do: nested?

  def key(:element, %{id: id, label: label, nested?: nested?}),
    do: Attrs.pagination(id, Said.say(label(label)), nested?)

  def key(:range, %{id: id}), do: %{"id" => "#{id}-range"}

  def key(to, %{id: id, page: page, target: target}) when to in [:previous, :next] do
    Map.merge(
      %{"id" => "#{id}-#{to}", "disabled" => is_nil(Map.fetch!(page, to))},
      Attrs.page(id, Atom.to_string(to), target)
    )
  end

  # the page numbers, where the pages are counted (offset pagination)
  def key(:pages, %{id: id, page: page, state: state, model: model, target: target}) do
    if model.pagination.strategy == :offset do
      for number <- numbers(page, state) do
        current? = number == state.page

        %{
          number: number,
          current?: current?,
          button:
            Map.merge(
              %{
                "id" => "#{id}-page-#{number}",
                "aria-label" => Said.say(go_to(number)),
                "aria-current" => current? && "page"
              },
              Attrs.page(id, number, target)
            )
        }
      end
    else
      []
    end
  end

  # "Rows per page", where the table offers page sizes; else nil
  def key(:sizes, %{id: id, model: model, state: state, target: target}) do
    sizes = model.pagination.page_sizes
    chosen = Model.Pagination.size(model.pagination, state.per)

    if sizes != [] do
      %{
        form: Attrs.page_size(id, target),
        label: %{"for" => "#{id}-page-size"},
        select: %{"id" => "#{id}-page-size", "name" => "size"},
        options: for(size <- sizes, do: %{size: size, chosen?: size == chosen})
      }
    end
  end

  def key(words, given) when words in [:texts, :messages], do: Map.fetch!(words(given), words)

  defp words(%{page: page, row_count: row_count, state: state, label: label}) do
    Said.words(
      label: label(label),
      range: range(page, row_count, state),
      previous: Said.t(:previous),
      next: Said.t(:next),
      rows_per_page: Said.t(:rows_per_page),
      go_to_page: Enum.map(numbers(page, state), &go_to/1)
    )
  end

  defp label(label), do: Said.t(:pagination, table: label)
  defp go_to(number), do: Said.t(:go_to_page, page: number)

  # The page numbers offered: the first, the last and those around the
  # current one, of the pages there are; and the current one, also when the
  # URL asked for a page beyond the last. Without a total only the current
  # page is known.
  defp numbers(%{pages: pages}, %{page: current}) when is_integer(pages) do
    [1, pages | Enum.to_list((current - 2)..(current + 2)//1)]
    |> Enum.filter(&((&1 >= 1 and &1 <= pages) or &1 == current))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp numbers(_page, %{page: current}), do: [current]

  # What the range of the page says.
  defp range(%{offset: offset, total: total}, row_count, _state)
       when is_integer(offset) and row_count > 0 do
    bindings = [from: offset + 1, to: offset + row_count, total: total]

    if total,
      do: Said.t(:range_of_total, bindings),
      else: Said.t(:range, Keyword.delete(bindings, :total))
  end

  defp range(%{offset: offset}, _row_count, state) when is_integer(offset),
    do: Said.t(:page, page: state.page)

  defp range(%{total: total}, _row_count, _state) when is_integer(total),
    do: Said.t(:records, count: total)

  defp range(_page, _row_count, _state), do: nil
end
