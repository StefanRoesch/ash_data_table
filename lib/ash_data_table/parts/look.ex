defmodule AshDataTable.Parts.Look do
  @moduledoc false
  # The look of `Kit.Default`'s tables: the rules its root's class holds
  # beside the structural ones (`Parts.Grid.root/0`), written once per page
  # on the root of the table on the page and reaching every table inside
  # it, nested tables and pickers' tables too. The default look is always
  # there; an option of the look (`AshDataTable.Kit`, "The look of a
  # table") adds its rules only where it is on, so a page sends no rule it
  # does not use.
  #
  # The rules find a grid's parts by their markers, not their tags, so a
  # kit of `div`s that keeps `Kit.Default`'s root class looks the same:
  #
  #   * the header group: the child of the grid whose rows hold the column
  #     headers (`:has(>[role=row]>[role=columnheader])`); its last row is
  #     the filter row;
  #   * a record's row group: a `role=rowgroup` child of the grid that is
  #     no detail (`data-detail`); the cells of its row are the record's;
  #   * a detail: the row group under a record with its lines and nested
  #     tables; its row group's record is open while the expander says so
  #     (`aria-expanded=true`).
  #
  # A rule about a grid's own rows goes through `>` from the grid, so that
  # it never reaches into a nested table, which stands in a cell; the
  # nested table has the same rules for itself.
  #
  # Every tint is mixed from the theme's colours (`--color-base-content`,
  # `--color-primary`), so it follows the host's daisyUI theme, light and
  # dark. A tint is a background image, not a background colour: it lies
  # over the ground the grid's hook gives the cells that stay in view
  # (`sticky_label?`), so a row is tinted alike across them. Forced colours
  # take tints away: lines and borders carry the structure there.
  #
  # Written out in full, as Tailwind finds a class only as it is written in
  # the source.

  @default Enum.join(
             [
               # The tints, by name: the hover of a row, the open row, a
               # stripe.
               "[--ash-data-table-hover:color-mix(in_oklab,var(--color-base-content)_5%,transparent)] [--ash-data-table-open:color-mix(in_oklab,var(--color-primary)_10%,transparent)] [--ash-data-table-stripe:color-mix(in_oklab,var(--color-base-content)_3%,transparent)]",
               # The two lines in one table share it: a separate border
               # model with no spacing, so that each cell draws its own
               # line, and a sticky header keeps the rule under it (a
               # collapsed border is the table's, and stays behind).
               # Every number with digits of one width.
               "[&_[role=grid]]:border-separate [&_[role=grid]]:border-spacing-0 [&_[role=grid]]:tabular-nums",
               # Horizontal lines only, one under each record, a little
               # stronger than daisyUI's: its line is under a `tr`, which a
               # separate border model does not draw.
               "[&_[role=grid]>[role=rowgroup]:not([data-detail])>[role=row]>[role=gridcell]]:border-b [&_[role=grid]>[role=rowgroup]:not([data-detail])>[role=row]>[role=gridcell]]:border-base-content/15",
               # The row the pointer is over, and the open row: its record
               # stays tinted while its lines are open, with a bar at its
               # left edge, over which the line of the nested area goes on
               # (below). Of the three tints the open row's wins, then the
               # hover, then a stripe: by the weight of their selectors (a
               # stripe's is a `:where`).
               "[&_[role=grid]>[role=rowgroup]:not([data-detail])>[role=row]:hover>[role=gridcell]]:[background-image:linear-gradient(var(--ash-data-table-hover),var(--ash-data-table-hover))]",
               "[&_[role=grid]>[role=rowgroup]:has(>[role=row]>[data-expander]>button[aria-expanded=true])>[role=row]>[role=gridcell]]:[background-image:linear-gradient(var(--ash-data-table-open),var(--ash-data-table-open))]",
               "[&_[role=grid]>[role=rowgroup]:has(>[role=row]>[data-expander]>button[aria-expanded=true])>[role=row]>[role=gridcell]:first-child]:shadow-[inset_3px_0_0_color-mix(in_oklab,var(--color-primary)_70%,transparent)]",
               # forced colours take the bar away: there it is a border
               "forced-colors:[&_[role=grid]>[role=rowgroup]:has(>[role=row]>[data-expander]>button[aria-expanded=true])>[role=row]>[role=gridcell]:first-child]:border-s-[3px]",
               # The header and the filter row are one group, on the ground
               # of the table (also where it stays in view, `sticky_header`),
               # with one stronger rule under it; the header's labels in
               # daisyUI's muted header colour.
               "[&_[role=grid]>:has(>[role=row]>[role=columnheader])>[role=row]>*]:bg-[var(--ash-data-table-ground,var(--ash-data-table-default-ground))]",
               "[&_[role=grid]>:has(>[role=row]>[role=columnheader])>[role=row]:last-child>*]:border-b-2 [&_[role=grid]>:has(>[role=row]>[role=columnheader])>[role=row]:last-child>*]:border-base-content/30",
               "[&_[role=grid]>:has(>[role=row]>[role=columnheader])>[role=row]:first-child>*]:pb-1 [&_[role=grid]>:has(>[role=row]>[role=columnheader])>[role=row]:last-child>*]:pt-0",
               # the footer's row of summaries, under a line as the header
               "[&_[role=grid]_[data-summaries]>*]:border-t [&_[role=grid]_[data-summaries]>*]:border-base-content/15",
               # A number stands at the end of its cell, and its header
               # with it (`data-number`).
               "[&_[role=grid]_[data-number]]:text-end",
               # daisyUI's `checkbox-xs` rounds its corners with the
               # theme's radius of a selector, which is a circle at that
               # size in some themes: a box that selects is square, never
               # round as a radio button.
               "[&_.checkbox]:rounded-[min(var(--radius-selector),0.1875rem)]",
               # The nested area under an open row: one line in the primary
               # colour, at reduced strength, down its left, which starts
               # under the open row's bar, and one inset after it, about an
               # expander wide, for each level. The line is drawn by the
               # parts that stay at the left edge of the scroll area, the
               # line's own (`Parts.Related.line`) and the nested table's
               # view (`data-ash-data-table-view`), so that it stays where
               # it is as the table scrolls sideways. Below each nested
               # table a little of the line, and before the next line the
               # rest of about one row's height. Every level has the same:
               # its own line and its one inset, in the same colour.
               "[&_[data-nested]_[data-ash-data-table-view]]:border-s-[3px] [&_[data-nested]_[data-ash-data-table-view]]:border-s-primary/45 [&_[data-nested]_[data-ash-data-table-view]]:ps-5 [&_[data-nested]_[data-ash-data-table-view]]:pb-3",
               "[&_[role=grid]>[role=rowgroup][data-detail]>[role=row]:first-child>[data-line]>div]:pt-3 [&_[role=grid]>[role=rowgroup][data-detail]>[role=row]:has(>[data-nested])+[role=row]>[data-line]>div]:pt-3",
               # Where the nested area ends: one stronger rule.
               "[&_[role=grid]>[role=rowgroup][data-detail]>[role=row]:last-child>[role=gridcell]]:border-b-2 [&_[role=grid]>[role=rowgroup][data-detail]>[role=row]:last-child>[role=gridcell]]:border-base-content/25",
               # A nested table's scroll area is a stacking context of its
               # own: whatever in it stays in view (its header, its label
               # column) is drawn inside it, and never over the header of
               # the table it is in.
               "[&_[data-nested]_[data-ash-data-table]]:isolate"
             ],
             " "
           )

  # How high the rows are: the padding of every cell of a grid, but a cell
  # that spans it (a line, a nested table's cell, a nested table's pages),
  # which has its own. The text keeps its size.
  @density %{
    compact:
      "[&_[role=grid]>*>[role=row]>:not([colspan])]:px-3 [&_[role=grid]>*>[role=row]>:not([colspan])]:py-1",
    normal:
      "[&_[role=grid]>*>[role=row]>:not([colspan])]:px-3 [&_[role=grid]>*>[role=row]>:not([colspan])]:py-2",
    roomy:
      "[&_[role=grid]>*>[role=row]>:not([colspan])]:px-4 [&_[role=grid]>*>[role=row]>:not([colspan])]:py-3"
  }

  # Every other record, counted over the records' row groups only: a
  # detail between two of them is not counted, nor is the header group.
  # (daisyUI's `table-zebra` counts the rows of one `tbody`, and here every
  # record is a row group of its own.)
  @stripes "[&_[role=grid]>:where([role=rowgroup]:nth-child(even_of_[role=rowgroup]:not([data-detail],:has(>[role=row]>[role=columnheader]))))>[role=row]>[role=gridcell]]:[background-image:linear-gradient(var(--ash-data-table-stripe),var(--ash-data-table-stripe))]"

  # A line between the columns, in the header too; not before the first.
  @column_lines "[&_[role=grid]>*>[role=row]>:not(:first-child,[colspan])]:border-s [&_[role=grid]>*>[role=row]>:not(:first-child,[colspan])]:border-s-base-content/10"

  # The header that stays in view, the Airtable way: each grid is its own
  # scroll area, both ways, as high as `height` (a nested table's as
  # `nested_height`, about ten rows), and its header group sticks to its
  # top with plain CSS. The header of the table on the page is drawn over
  # everything nested (each nested scroll area is a stacking context of
  # its own, above); the corner, the label column's header where it stays
  # in view too (`sticky_label?`), is in the header group, and so over the
  # label cells under it. A cell that gets the focus is scrolled into view
  # below the header group, not under it (`scroll-padding-top`, about as
  # high as the header group). The scroll area's corners are square: a
  # rounded corner clips the header and the rows under it alike, and the
  # rows show through its edge while they scroll. The scrollbar at the
  # bottom edge of the window is not shown: the grid's own is in view.
  @sticky_header Enum.join(
                   [
                     "[&_[data-ash-data-table]]:max-h-[var(--ash-data-table-height,min(75dvh,48rem))] [&_[data-ash-data-table]]:overflow-y-auto [&_[data-ash-data-table]]:rounded-none",
                     "[&_[data-nested]_[data-ash-data-table]]:max-h-[var(--ash-data-table-nested-height,28rem)]",
                     "[&_[role=grid]>:has(>[role=row]>[role=columnheader])]:sticky [&_[role=grid]>:has(>[role=row]>[role=columnheader])]:top-0 [&_[role=grid]>:has(>[role=row]>[role=columnheader])]:z-10",
                     "[&_[data-scrollbar]]:hidden!"
                   ],
                   " "
                 )

  # how high the header group is, by density, for `scroll-padding-top`
  @scroll_padding %{
    compact: "[&_[data-ash-data-table]]:scroll-pt-16",
    normal: "[&_[data-ash-data-table]]:scroll-pt-18",
    roomy: "[&_[data-ash-data-table]]:scroll-pt-20"
  }

  @doc false
  # The classes of the look of the table on the page, for its root.
  def root(look) do
    Enum.join(
      [@default, @density[look.density]] ++
        if(look.stripes, do: [@stripes], else: []) ++
        if(look.column_lines, do: [@column_lines], else: []) ++
        if(look.sticky_header,
          do: [@sticky_header, @scroll_padding[look.density]],
          else: []
        ),
      " "
    )
  end

  @doc false
  # The root's `style` of the look, as attributes to spread: the heights a
  # table was given, as custom properties (checked as CSS lengths,
  # `AshDataTable.Kit.look!/2`); nil where none was.
  def style(look) do
    case Enum.reject(
           [
             look.height && "--ash-data-table-height:#{look.height}",
             look.nested_height && "--ash-data-table-nested-height:#{look.nested_height}"
           ],
           &is_nil/1
         ) do
      [] -> nil
      heights -> %{"style" => Enum.join(heights, ";")}
    end
  end
end
