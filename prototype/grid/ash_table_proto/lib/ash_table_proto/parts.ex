defmodule AshTableProto.Parts do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). The markup the three rendering variants share:
  header, one row (with its optional nested table), pager and editor templates.

  The variants differ only in how rows are held and diffed (keyed `:for`,
  stream, one LiveComponent per row); the cell markup is the same so the
  measurements compare strategies and not markup.
  """
  use Phoenix.Component
  alias AshTableProto.Model

  @hook "AshTableProto.Hook.Grid"
  def hook, do: @hook

  @col_rem 11
  @expander_rem 2

  @doc """
  `layout: :fixed` in the table config gives every column a declared width and
  the table `table-layout: fixed`, so the browser does not have to measure
  every cell again when one cell changes. `:auto` is the browser default.
  """
  def table_style(%{layout: :fixed}, columns, nested) do
    width = length(columns) * @col_rem + offset(nested) * @expander_rem
    "table-layout:fixed;width:#{width}rem"
  end

  def table_style(_cfg, _columns, _nested), do: nil

  defp th_style(:fixed), do: "width:#{@col_rem}rem"
  defp th_style(_), do: nil
  defp x_style(:fixed), do: "width:#{@expander_rem}rem"
  defp x_style(_), do: nil

  attr :gid, :string, required: true
  attr :columns, :list, required: true
  attr :sort, :any, required: true
  attr :nested, :any, required: true
  attr :layout, :atom, default: :auto

  def thead(assigns) do
    ~H"""
    <thead id={"#{@gid}-h"}>
      <tr role="row" aria-rowindex="1">
        <th
          :if={@nested}
          id={"#{@gid}-h-x"}
          role="columnheader"
          aria-colindex="1"
          tabindex="-1"
          style={x_style(@layout)}
          class="w-8 px-2 py-1 focus:outline-2 focus:-outline-offset-2 focus:outline-primary"
        >
          <span class="sr-only">{@nested.label}</span>
        </th>
        <th
          :for={col <- @columns}
          id={"#{@gid}-h-#{col.ci}"}
          role="columnheader"
          aria-colindex={col.ci + 1 + offset(@nested)}
          aria-sort={aria_sort(@sort, col)}
          tabindex="-1"
          data-ci={col.ci}
          data-col={col.name}
          data-type={col.type}
          data-edit={to_string(col.editable)}
          style={th_style(@layout)}
          class="truncate cursor-pointer select-none whitespace-nowrap px-2 py-1 text-left focus:outline-2 focus:-outline-offset-2 focus:outline-primary"
        >
          {col.label}<span aria-hidden="true">{sort_mark(@sort, col)}</span>
        </th>
      </tr>
    </thead>
    """
  end

  defp aria_sort({name, :asc}, %{name: name}), do: "ascending"
  defp aria_sort({name, :desc}, %{name: name}), do: "descending"
  defp aria_sort(_, _), do: "none"

  defp sort_mark({name, :asc}, %{name: name}), do: " ▲"
  defp sort_mark({name, :desc}, %{name: name}), do: " ▼"
  defp sort_mark(_, _), do: ""

  def offset(nil), do: 0
  def offset(_nested), do: 1

  attr :id, :string, required: true
  attr :gid, :string, required: true
  attr :row, :map, required: true
  attr :columns, :list, required: true
  attr :nested, :any, required: true

  @doc """
  One row as a `<tbody>`: the row itself plus, when open, the row holding its
  nested table. A SINGLE root element on purpose: the LiveView client can then
  skip an unchanged row when it re-renders the grid (the `data-phx-skip`
  optimisation only applies to function components with one root tag).
  """
  def row(assigns) do
    ~H"""
    <tbody id={@id} class="border-t border-base-300">
      <.row_inner gid={@gid} row={@row} columns={@columns} nested={@nested} />
    </tbody>
    """
  end

  attr :gid, :string, required: true
  attr :row, :map, required: true
  attr :columns, :list, required: true
  attr :nested, :any, required: true

  def row_inner(assigns) do
    ~H"""
    <tr id={"#{@gid}-#{@row.id}-r"} role="row" aria-rowindex={@row.idx} data-pk={@row.id}>
      <td
        :if={@nested}
        id={"#{@gid}-#{@row.id}-x"}
        role="gridcell"
        aria-colindex="1"
        tabindex="-1"
        data-x
        class="px-2 py-1 focus:outline-2 focus:-outline-offset-2 focus:outline-primary"
      >
        <button
          type="button"
          tabindex="-1"
          aria-expanded={to_string(@row.open)}
          aria-label={"#{@nested.label} of row #{@row.id}"}
          class="cursor-pointer"
        >
          {if @row.open, do: "▾", else: "▸"}
        </button>
      </td>
      <td
        :for={c <- Model.cells(@row, @columns, @gid, offset(@nested))}
        :key={c.ci}
        role="gridcell"
        tabindex="-1"
        class="max-w-80 truncate px-2 py-1 focus:outline-2 focus:-outline-offset-2 focus:outline-primary aria-busy:opacity-50 aria-invalid:bg-error/15"
        {c.attrs}
      >{body(c)}</td>
    </tr>
    <tr :if={@row.open} id={"#{@gid}-#{@row.id}-d"} role="row">
      <td
        id={"#{@gid}-#{@row.id}-dc"}
        role="gridcell"
        aria-colindex="1"
        tabindex="-1"
        data-detail
        colspan={length(@columns) + 1}
        class="bg-base-200 py-2 pr-2 pl-8 focus:outline-2 focus:-outline-offset-2 focus:outline-primary"
      >
        <.live_component
          module={@nested.module}
          id={"#{@gid}-#{@row.id}-n"}
          cfg={@nested.cfg}
          cols={:all}
          page_size={@nested.cfg.page_size}
          scope={{@nested.destination_attribute, Map.get(@row.rec, @nested.source_attribute)}}
        />
      </td>
    </tr>
    """
  end

  # The common case is a plain string: one dynamic slot and no nested template.
  defp body(%{kind: :plain, text: text}), do: text
  defp body(c), do: special(%{c: c})

  defp special(%{c: %{kind: :bool}} = assigns) do
    ~H"""
    <input
      type="checkbox"
      tabindex="-1"
      class="checkbox checkbox-xs"
      checked={@c.text == "true"}
      disabled={@c.ro}
      aria-label={@c.label}
    /><span :if={@c[:msg]} role="alert" class="block whitespace-normal text-xs text-error">{@c.msg}</span>
    """
  end

  defp special(%{c: %{kind: :invalid}} = assigns) do
    ~H"""
    <span data-v>{@c.text}</span><span role="alert" class="block whitespace-normal text-xs text-error">{@c.msg}</span>
    """
  end

  attr :gid, :string, required: true
  attr :columns, :list, required: true

  @doc "One inert editor template per editable column; the hook clones it into the cell."
  def editors(assigns) do
    ~H"""
    <div id={"#{@gid}-ed"} data-editors hidden>
      <template
        :for={col <- @columns}
        :if={col.editable and col.type != :boolean}
        id={"#{@gid}-ed-#{col.name}"}
        data-ci={col.ci}
      >
        <select
          :if={col.type == :enum}
          data-editor
          aria-label={"Edit #{col.label}"}
          class="select select-xs w-full min-w-28"
        >
          <option :for={opt <- col.options} value={opt}>{opt}</option>
        </select>
        <input
          :if={col.type != :enum}
          data-editor
          type={input_type(col.type)}
          step={col[:step]}
          aria-label={"Edit #{col.label}"}
          class="input input-xs w-full min-w-28"
        />
      </template>
    </div>
    """
  end

  defp input_type(:number), do: "number"
  defp input_type(:date), do: "date"
  defp input_type(:datetime), do: "datetime-local"
  defp input_type(_), do: "text"

  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total, :integer, required: true
  attr :myself, :any, required: true

  def pager(assigns) do
    ~H"""
    <div :if={@total > @page_size} class="flex items-center gap-2 py-1 text-xs">
      <button
        type="button"
        class="btn btn-xs"
        data-pager="prev"
        phx-click="page"
        phx-value-to="prev"
        phx-target={@myself}
        disabled={@page == 1}
      >
        Previous
      </button>
      <span>
        rows {(@page - 1) * @page_size + 1} to {min(@page * @page_size, @total)} of {@total}
      </span>
      <button
        type="button"
        class="btn btn-xs"
        data-pager="next"
        phx-click="page"
        phx-value-to="next"
        phx-target={@myself}
        disabled={@page * @page_size >= @total}
      >
        Next
      </button>
    </div>
    """
  end
end
