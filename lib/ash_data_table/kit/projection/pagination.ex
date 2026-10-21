defmodule AshDataTable.Kit.Projection.Pagination do
  @moduledoc false
  # The projection of the `pagination` part (`AshDataTable.Kit.Projection`),
  # under a table on the page and in a nested table's footer: the range,
  # Previous, the page numbers offered, Next and "Rows per page".

  alias AshDataTable.Attrs
  alias AshDataTable.Kit.Projection.Said
  alias AshDataTable.Model

  @doc false
  # Whether there are pages to go through.
  def pages?(page, model), do: not is_nil(page) and model.pagination.strategy != :none

  @doc false
  def of(%{id: id, nested?: nested?, page: page, model: model, state: state} = given) do
    target = given.target
    numbers = numbers(page, state)

    words =
      Said.words(
        label: Said.t(:pagination, table: given.label),
        range: range(page, given.row_count, state),
        previous: Said.t(:previous),
        next: Said.t(:next),
        rows_per_page: Said.t(:rows_per_page),
        go_to_page: Enum.map(numbers, &Said.t(:go_to_page, page: &1))
      )

    sizes = model.pagination.page_sizes
    chosen = Model.Pagination.size(model.pagination, state.per)

    Map.merge(
      %{
        nested?: nested?,
        element: Attrs.pagination(id, words.texts.label, nested?),
        range: %{"id" => "#{id}-range"},
        previous:
          Map.merge(
            %{"id" => "#{id}-previous", "disabled" => is_nil(page.previous)},
            Attrs.page(id, "previous", target)
          ),
        next:
          Map.merge(
            %{"id" => "#{id}-next", "disabled" => is_nil(page.next)},
            Attrs.page(id, "next", target)
          ),
        # the page numbers, where the pages are counted (offset pagination)
        pages:
          if model.pagination.strategy == :offset do
            for {number, label} <- Enum.zip(numbers, words.texts.go_to_page) do
              current? = number == state.page

              %{
                number: number,
                current?: current?,
                button:
                  Map.merge(
                    %{
                      "id" => "#{id}-page-#{number}",
                      "aria-label" => label,
                      "aria-current" => current? && "page"
                    },
                    Attrs.page(id, number, target)
                  )
              }
            end
          else
            []
          end,
        # "Rows per page", where the table offers page sizes; else nil
        sizes:
          if sizes != [] do
            %{
              form: Attrs.page_size(id, target),
              label: %{"for" => "#{id}-page-size"},
              select: %{"id" => "#{id}-page-size", "name" => "size"},
              options: for(size <- sizes, do: %{size: size, chosen?: size == chosen})
            }
          end
      },
      words
    )
  end

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
