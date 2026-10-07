# Research: colour and visual design of an editable table

Research for the later theming slice. Run on 2026-10-07.

**Question.** How should a table like ours be coloured for the best experience of the people using it: alternating row backgrounds, row lines, hover, the focused cell, the header and filter row, cell states, nested tables, row actions and status values, and the tokens behind all of it? What does the evidence say, what do the leading design systems prescribe, what do leading products do, and what does accessibility require?

Labels used below:

- **Evidence**: an empirical study, with its numbers.
- **Prescribed**: what a design system says or ships, read in its documentation or in its source.
- **Practice**: what a product does.
- **Computed**: a contrast ratio I calculated (WCAG 2 relative luminance) from colour values that were read in a source. Not measured in a browser.
- **Inferred**: my conclusion from the above. Not something a source says.
- **Recalled**: from memory, not fetched in this session. Treat as unverified.

Every source is linked where it is used and listed again at the end. Where a documentation site would not render for the fetcher, the system's stylesheet or component source was read instead, which is the stronger source for colours anyway.

## Answer in brief

1. **Zebra striping is weakly supported by evidence and is not the default of any design system looked at.** Three studies by Jessica Enders found no consistent gain in speed or accuracy on a small roomy table, a gain in accuracy on three of eight questions on a long table under time pressure, and a preference for single-colour striping (31% ranked it first, 4% last), with lined tables close behind (20% first, 4% last). One small laboratory study (Lee, 2014, 13 participants) found visual search *worse* with shading. Carbon, Fluent, Material, Polaris, Primer, Spectrum, Lightning, SAP UI5, GOV.UK, USWDS, daisyUI, AG Grid's Quartz and Alpine themes and MUI all ship unstriped by default and most offer striping as an option. The exceptions are Excel tables, AG Grid's Balham theme and the macOS bordered table style.
2. **The default everywhere is thin horizontal lines, no vertical lines, a header set apart by weight and often a faint fill, and a row hover.** Carbon says the hover "should always be enabled"; NN/g names borders, striping and hover together as aids for keeping one's place.
3. **Where striping is offered it is very faint**: between 1.02:1 and 1.32:1 against the base row in the systems measured. Stephen Few's rule is "it doesn't take much"; too dark and it reads as highlighting.
4. **States are layered, and the fills never carry the state alone.** Stripe, then hover, then selected are fills of increasing strength; focus and invalid are rings drawn over whatever fill is there. Selection always has a checkbox, an error always has an icon or a message.
5. **Three accessibility findings concern ash_table as it is today** (all **Computed**, from the default Phoenix 1.8 theme):
   - The focus ring is drawn in `primary`. In the default Phoenix themes `primary` has a contrast of 2.75:1 (light) and 2.90:1 (dark) against `base-100`. WCAG 1.4.11 asks 3:1 of a focus indicator.
   - A failed cell is marked by a ring in `error` and nothing else that is visible at rest. In the dark theme the `error` ring and the `primary` focus ring have a contrast of 1.01:1 against each other: they differ by hue only. WCAG 1.4.1 asks for more than colour.
   - That ring is an inset box shadow. In Windows forced-colors mode box shadows are removed, so the failed state has no visible mark at all there.
6. **For nested tables, the systems that have them all use indentation or inset padding** (AG Grid 30 px of padding around a bordered detail grid, Carbon 3.5 rem, Polaris and Notion indentation). None marks the region by background alone. Without indentation, what remains and is supported by the sources is: the open parent row keeps a fill, the nested table's own header row marks the beginning, and one stronger rule under the last line of the region marks the end. Lines survive forced-colors mode; fills do not.
7. **Tokens.** AG Grid, Bootstrap and daisyUI's own table border all derive table tints by mixing the text colour into the background at a small percentage. That works in light and dark themes alike. daisyUI's `base-200` and `base-300` do not: their distance from `base-100` differs by theme (1.05:1 to 1.17:1) and in dark themes they are darker than the base, not lighter.

The recommendations are in [What this suggests for ash_table](#what-this-suggests-for-ash_table). They are for the owner to decide.

## Where ash_table stands

**Read** in `lib/ash_table/live/table_component.ex` at `4009d7d`:

- The grid is a `<table class="table">` (daisyUI). No `table-zebra`, no hover class, no size class.
- From daisyUI's `.table`: cells `px-4 py-3`, 14 px text, a bottom border on every row of `color-mix(in oklch, var(--color-base-content) 5%, #0000)`, header and footer text in `base-content/60` at weight 600 ([table.css](https://github.com/saadeghi/daisyui/blob/master/packages/daisyui/src/components/table.css)).
- Focused cell: `outline-2 -outline-offset-2 outline-primary`, kept while the cell's editor has the focus.
- Failed cell: `inset-ring-2 inset-ring-error` on `td[aria-invalid]`, with the message in a popover named by `aria-describedby`.
- Saving cell, and a table that is reading: `opacity-60`.
- Read-only cell: `aria-readonly="true"`, no visual difference.
- Every row of the stream is a `<tbody>` of its own, and an expanded row's relationship lines and nested tables are a second `<tbody data-detail>` after it. This matters for striping, see [question 1](#1-zebra-striping).

**Computed** for the two themes a new Phoenix 1.8 app ships with ([app.css.eex](https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_assets/app.css.eex); the demo uses the same values) and for daisyUI 5's own defaults ([light.css](https://github.com/saadeghi/daisyui/blob/master/packages/daisyui/src/themes/light.css), [dark.css](https://github.com/saadeghi/daisyui/blob/master/packages/daisyui/src/themes/dark.css)). Ratios against `base-100` unless stated:

| | Phoenix light | Phoenix dark | daisyUI light | daisyUI dark |
| --- | --- | --- | --- | --- |
| `base-100`, `base-200`, `base-300` | `#f8f8f8` `#f2f2f2` `#e4e4e7` | `#292f37` `#1e2329` `#13171c` | `#ffffff` `#f8f8f8` `#eeeeee` | `#1d232a` `#191e24` `#15191e` |
| `base-200` (the `table-zebra` stripe) | 1.05 | 1.17 | 1.06 | 1.06 |
| `base-300` | 1.19 | 1.33 | 1.16 | 1.11 |
| `base-content` text | 16.7 | 12.6 | 17.7 | 14.8 |
| `base-content` text on `base-200` | 15.8 | 14.7 | 16.7 | 15.6 |
| header text `base-content/60` | 5.2 | 5.2 | 5.4 | 5.7 |
| text at `opacity-60` (a saving cell) | 4.5 | 5.6 | 4.7 | 6.2 |
| text at `opacity-60` on `base-200` | 4.5 (4.48) | 6.2 | 4.5 | 6.4 |
| **`primary` (the focus ring)** | **2.75** | **2.90** | 8.3 | 3.4 |
| **`error` (the failed ring)** | 4.3 | **2.94** | **2.9** | 5.5 |
| `primary` against `error` | 1.57 | **1.01** | 2.9 | 1.6 |
| row line, `base-content` 5% | 1.12 | 1.14 | 1.12 | 1.12 |
| `base-content` 10% / 20% / 30% | 1.25 / 1.61 / 2.11 | 1.30 / 1.72 / 2.31 | 1.26 / 1.62 / 2.12 | 1.27 / 1.70 / 2.33 |

Three things follow, all **Inferred** from the numbers:

- `primary` is a brand colour and a host theme may set it to anything. It is not safe as the colour of a focus ring. `base-content` is: daisyUI's contract is that a content colour "must have clear contrast" with its base ([daisyUI llms.txt](https://daisyui.com/llms.txt)), and it measures 12.6:1 or more in all four themes.
- `text-error` on `base-100` is below 4.5:1 in three of the four themes, so `error` is usable as a ring or an icon colour in some themes but not as the colour of small text. The current popover is right to use `text-base-content` with an `error` border.
- A `base-200` stripe is at the low end of what the other systems use (see [question 1](#1-zebra-striping)) and, in the Phoenix light theme, at the edge of what can be seen at all.

## 1. Zebra striping

### Evidence

- **Enders, study 1** (2008, 244 people, internet). A table of 15 rows and 9 columns, no scrolling, six questions, striped and plain. "No statistically significant difference in accuracy". Speed was slower with stripes on two questions and faster on four; only one difference was significant. 46% preferred striping, 33% had no preference. Her conclusion: "This experiment yielded no evidence that zebra striping consistently improves the accuracy or speed of tasks." Participants spontaneously followed rows with a finger or by selecting them with the mouse. ([A List Apart, "Zebra Striping: Does it Really Help?"](https://alistapart.com/article/zebrastripingdoesithelp/))
- **Enders, study 2** (2008, 2,276 sessions). A longer table with blank cells that probably needed scrolling, "similar to an online banking statement", 15 seconds per question, each question shown plain, lined or striped at random. "For three of the eight questions, the striped version yielded a more accurate response than did the plain and lined versions"; a fourth was close to significance; for the other four the three styles could not be told apart. Striping was never worse. ([A List Apart, "Zebra Striping: More Data for the Case"](https://alistapart.com/article/zebrastripingmoredataforthecase/))
- **Enders, study 3** (2008, over 1,200 Australians, a Newspoll panel, ranking six styles). Single-colour single-row striping: 31% ranked it first, 4% last. Lined: 20% first, 4% last. Two-colour striping: 23% first, 15% last. Triple striping: under 10% first, 28% last. Her advice: "the safest option is to shade the alternating, individual rows of your table with a single color", and where that costs too much, "stick with a plain or lined design". She lists what was not tested: row and column density, colours, contrast. (same article)
- **Lee, 2014** (MS thesis, University of Kentucky; a version appeared in the Proceedings of the Human Factors and Ergonomics Society). 13 participants searched a grid for a target with no shading, alternate rows shaded, or alternate columns shaded. "Overall performance was reliably better when the grid had no shading"; "the presence of any type of shading reduced search performance". The task was a serial search for a conjunctive target, not reading across a row. ([UKnowledge](https://uknowledge.uky.edu/psychology_etds/51))
- **Nielsen Norman Group** names the problem striping is meant to solve as one of four tasks in a data table (comparing data): "Borders, zebra striping, and hover-triggered highlighting of a record can all help". It cites no measurement. ([Data Tables: Four Major User Tasks](https://www.nngroup.com/articles/data-tables/))
- **Stephen Few**, *Show Me the Numbers* (2nd edition, chapter 8), expert guidance, not a study: white space is "the preferred means"; when rows are wide and white space cannot do it, "fill colors usually work better than grids and rules"; of the stripe, "it doesn't take much"; too dark and "it looks like every other row has been highlighted" and "scanning down a column of numbers is complicated". (Read in a copy of the chapter hosted by a university: [Few 2012, chapter 8](https://fenix.iseg.ulisboa.pt/downloadFile/1407508027555973/Few_2012_Chpt-8.pdf).)

What the evidence supports, **Inferred**: striping helps most when a row has to be followed across a long distance under load (many columns, dense rows, scrolling), and helps little or nothing on a short, roomy table with few columns. No study found was done on an *editable* grid, on a table with a hover, or on one with nested content. No study compares stripe strengths.

### Prescribed

| System | Default | Option | Stripe | Source |
| --- | --- | --- | --- | --- |
| IBM Carbon | off | "zebra stripes modifier ... to make scanning horizontal information easier" | `$layer-accent` on `$layer`: `#e0e0e0` on `#f4f4f4`, 1.20:1 (White theme); 1.31:1 (Gray 100) | [usage](https://carbondesignsystem.com/components/data-table/usage/), [_data-table.scss](https://github.com/carbon-design-system/carbon/blob/main/packages/styles/scss/components/data-table/_data-table.scss), [themes.json](https://github.com/carbon-design-system/carbon/blob/main/packages/themes/src/dtcg/themes.json) |
| Microsoft Fluent 2 | off | none in the component | none | [useTableRowStyles](https://github.com/microsoft/fluentui/blob/master/packages/react-components/react-table/library/src/components/TableRow/useTableRowStyles.styles.ts) |
| Material (web component, Material 2) | off | none | none | [_data-table-theme.scss](https://github.com/material-components/material-components-web/blob/master/packages/mdc-data-table/_data-table-theme.scss) |
| Shopify Polaris | off | `IndexTable` and `DataTable` have a zebra variant | `bg-surface` and `bg-surface-secondary` | [IndexTable.module.css](https://github.com/Shopify/polaris/blob/main/polaris-react/src/components/IndexTable/IndexTable.module.css) |
| GitHub Primer | off | none | none | [Table.module.css](https://github.com/primer/react/blob/main/packages/react/src/DataTable/Table.module.css) |
| Adobe Spectrum | off | none | none | [spectrum-css table](https://github.com/adobe/spectrum-css/blob/main/components/table/index.css) |
| Salesforce Lightning | off | `slds-table_striped` | the hover colour, on even rows | [data-tables/base](https://github.com/salesforce-ux/design-system/blob/master/ui/components/data-tables/base/_index.scss) |
| SAP UI5 (Fiori) | `alternateRowColors` default `false`, in the responsive and the grid table | yes | not read | [sap.ui.table.Table](https://github.com/SAP/openui5/blob/master/src/sap.ui.table/src/sap/ui/table/Table.js), [sap.m.Table](https://github.com/SAP/openui5/blob/master/src/sap.m/src/sap/m/Table.js) |
| GOV.UK | off | none | none | [_mixin.scss](https://github.com/alphagov/govuk-frontend/blob/main/packages/govuk-frontend/src/govuk/components/table/_mixin.scss) |
| USWDS | off (bordered) | `usa-table--striped`: "improve readability by visually grouping row content" | `base-lightest`; the text colour is recomputed for the stripe | [table](https://designsystem.digital.gov/components/table/), [settings](https://github.com/uswds/uswds/blob/develop/packages/uswds-core/src/styles/settings/_settings-components.scss) |
| Apple (macOS) | on in the bordered style | `usesAlternatingRowBackgroundColors`, `alternatingRowBackgrounds(_:)` | system colours | [HIG, Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) |
| daisyUI 5 | off | `table-zebra` | `base-200` on even rows, 1.05 to 1.17:1 | [table.css](https://github.com/saadeghi/daisyui/blob/master/packages/daisyui/src/components/table.css) |
| Bootstrap 5 | off | `table-striped` | 5% of the emphasis colour, about 1.12:1 | [_variables.scss](https://github.com/twbs/bootstrap/blob/main/scss/_variables.scss) |
| Tailwind (docs example) | n/a | `odd:` and `even:` variants | `white` and `gray-50`, 1.05:1 | [docs](https://tailwindcss.com/docs/hover-focus-and-other-states) |
| AG Grid Quartz, Alpine | off: `oddRowBackgroundColor` is the data background | a theme parameter | n/a | [core-css.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/core/core-css.ts) |
| AG Grid Balham | on | | half of the chrome colour, about 1.02:1 | [themes.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/parts/theme/themes.ts) |
| MUI X Data Grid | off | by a row class, shown in the docs | the app's choice | [style docs](https://github.com/mui/mui-x/blob/master/docs/data/data-grid/style/style.md) |

Apple is the only one that says when: "Consider using alternating row colors in a multicolumn table. Alternating colors can help people track row values across columns, especially in a wide table."

SAP adds a restriction that bears on nesting: "Alternate row coloring is not available for the tree mode."

### Conflicts with other states

- **Hover and selection.** AG Grid draws hover and selection as an overlay above the stripe "so that they overlay on top of the alternating row backgrounds rather than replacing them" ([_grid-layout.css](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/core/css/_grid-layout.css)). Carbon's stylesheet has a separate set of rules for zebra combined with each of hover, selection and expansion. daisyUI steps the hover up one shade on a striped table (`base-200` plain, `base-300` striped). **Inferred**: with stripes, every fill needs a second value or has to be translucent.
- **Lines.** Carbon's zebra table has no visible row lines: each row's border takes the colour of its own fill. **Inferred**: stripes and lines are two answers to the same question; a table gets one of them.
- **Text contrast.** WCAG 1.4.3 is measured against the background the text is actually on, so every text colour must pass on the stripe as well as on the base. USWDS computes the stripe's text colour separately for that reason. **Computed**: with a `base-200` stripe, body text is fine everywhere; a saving cell at `opacity-60` falls to 4.48:1 on the stripe in the Phoenix light theme.
- **Editable cells.** No source found speaks to it. **Inferred**: an editor with a transparent background (ours) shows the stripe through it, which is right; an editor with its own `base-100` field would punch a hole into a striped row.
- **Nested content.** Carbon stripes the parent row and its expanded row as one unit, so the stripe counts records, not table rows ([_data-table-expandable.scss](https://github.com/carbon-design-system/carbon/blob/main/packages/styles/scss/components/data-table/expandable/_data-table-expandable.scss)). SAP disables striping for trees. See [question 6](#6-nested-tables).
- **Our markup.** `table-zebra` matches `tbody tr:nth-child(even)`. With one `<tbody>` per row that never matches a data row, and counting `<tbody>` elements instead would count the detail bodies of expanded rows too. **Inferred**: striping here needs `tbody:nth-child(even of :not([data-detail]))` (supported by all current browsers) or a parity the server writes; the daisyUI class cannot be used as it is.

## 2. Row separation

**Prescribed and practice.**

- **Horizontal hairlines only** is the default of Carbon (`$border-subtle`, 1.55:1 on the row), Fluent (`colorNeutralStroke2`), Material (12% of the text colour), Primer, Spectrum (`gray-300`), GOV.UK (1 px in the border colour), Lightning's bordered table, daisyUI (5% of the text colour, 1.12:1), shadcn/ui (`border-b`) and AG Grid (`rowBorder: true`, 15% of the text colour, about 1.36:1).
- **Vertical lines** are off by default in all of them. AG Grid's `columnBorder` is transparent by default; Lightning has `slds-table_col-bordered` as an option; USWDS is the exception, with a 1 px border on every cell by default and a "borderless" variant "when you want the information to feel more a part of the text it accompanies".
- **Full grid lines** are the look of spreadsheets: Excel, Google Sheets, Airtable's grid view (**Recalled**), Glide Data Grid (one `borderColor` for both directions, `rgba(115, 116, 131, 0.16)`, with an optional separate `horizontalBorderColor`; [styles.ts](https://github.com/glideapps/glide-data-grid/blob/main/packages/core/src/common/styles.ts)).
- **Whitespace only**: Few's first choice for a table that has the room. No design system makes it the default of its data table.
- **Few on lines**: delineating rows and columns "is the least effective use of rules and grids"; lines "excessively fragment the data"; rules are useful to "group sections of data" and to separate "the headers and footers from the body"; "keep the lines thin and light"; and a light boundary around a table is useful "when you must place other objects (such as additional tables ...) close to the table".

**Inferred**, when each fits:

- Hairlines only: the general case, and ours. Lines cost nothing in forced-colors mode, where fills disappear.
- Whitespace only: short read-only tables with tall rows. Not an editable grid, where the cell is a target.
- Vertical lines: when the cell, not the row, is the unit people work in, that is, a dense grid in which most cells are editable, and when adjacent columns hold values that run into each other (numbers next to numbers). Otherwise alignment and padding separate columns.
- Line strength: daisyUI's 5% is the faintest of all the systems read. 10% (1.25 to 1.30:1) is nearer to AG Grid and still fainter than Carbon. WCAG sets no minimum for a row line, see the [checklist](#accessibility-constraints).

## 3. Hover, focused cell, focused row, selected row

**Prescribed.**

| | Row hover | Selected row | Focus |
| --- | --- | --- | --- |
| Carbon | `$layer-hover`; "should always be enabled as it can help the user visually scan the columns of data in a row even if the row is not interactive" | `$layer-selected` plus a checkbox; hover on selected is a further token | `$focus` (4.55:1 on the row), 2 px inset |
| Fluent 2 | `colorSubtleBackgroundHover` | `brand`: `colorBrandBackground2`; `neutral`: `colorSubtleBackgroundSelected`; a "subtle" mode shows the checkbox on hover and focus only | 2 px outline, `colorStrokeFocus2`, on the row |
| Material 2 web | 4% of the text colour | 4% of `primary`, with a checkbox | not read |
| Polaris | `bg-surface-hover` | `bg-surface-selected`, with a checkbox | not read |
| Primer | a transparent control hover | none in the component | not read |
| Spectrum | `gray-900` at a low opacity | `blue-900` at a low opacity ("emphasized") or `gray-700`; a stronger step on focus | a focus-indicator token for thickness and colour |
| Lightning | on by default, `slds-no-row-hover` turns it off | `$color-background-row-selected` | the focused cell: an inset 1 px shadow in an "accessible brand" colour, plus a fill |
| AG Grid | 8% of the accent colour (15% in dark) | 12% of the accent (20% in dark, 30% in Alpine); a range selection is 20% with a solid accent border | a 1 px solid border on the cell in the accent colour (`#2196f3`, 3.12:1 on white) |
| MUI X | the theme's `action.hover` at its hover opacity; removed under `@media (hover: none)` | `primary` at the selected opacity; selected and hovered adds the two opacities | 1 px solid outline in `primary`, inset 1 px |
| daisyUI | `row-hover` on a `<tr>`: `base-200`, or `base-300` on a striped table | the docs show `bg-base-200` for an "active" row | none for cells |
| Bootstrap | 7.5% of the emphasis colour | "active": 10% | n/a |
| shadcn/ui | `hover:bg-muted/50` | `data-[state=selected]:bg-muted`; a row that holds an expanded control gets `bg-muted/50` | n/a |

Atlassian states the principle in one line: "Never rely on highlighted rows to convey important meaning, selection, or focus." ([dynamic table](https://atlassian.design/components/dynamic-table/usage))

**How they layer**, **Inferred** from the table above; no system documents an order as such:

1. Base row.
2. Stripe: about 5% of the text colour.
3. Hover: about 7 to 10%. Stronger than the stripe, weaker than selection. Bootstrap's scale (5%, 7.5%, 10%) is the clearest statement of it.
4. Selected: a tint of the accent colour, not of grey, so that it is not confused with a stripe or a hover; plus the checkbox.
5. Selected and hovered: one more step (MUI adds the opacities, Carbon and Polaris have a token for it).
6. The focused cell: a ring, not a fill. It is drawn over all of the above, so it needs no rule for combinations.
7. The failed cell: a ring in another colour and a non-colour mark. When a failed cell is focused, both must stay visible: ours replaces neither, since one is an outline and one a shadow, but they are the same width in the same place, so the outline covers the shadow.

**Keeping them apart without colour**, **Inferred**:

- Hover needs nothing: the pointer is the cue. WCAG says so: hover treatments "do not themselves need to contrast 3:1 against the background" ([Understanding 1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)).
- Selection: a checked checkbox in the row (every system above) and `aria-selected`.
- Focus: a ring is a shape. It must reach 3:1 against what it is drawn on.
- A "focused row" highlight in addition to the focused cell is something only AG Grid does for full-width rows; the spreadsheet products highlight the row and column *headers* of the active cell instead (**Recalled**). For a cell-focused grid like ours the cell ring is the convention.
- Do not transition these fills slowly. Carbon uses its fastest duration (`$duration-fast-01`, 70 ms, **Recalled** value) for row backgrounds. A reader in Enders' comments describes the other side: sweeping the pointer across ten hovered rows gives "9 rapid on-off flashes".

## 4. Header and filter row

**Prescribed.**

- **A fill**: Carbon `$layer-accent` (the same token as the zebra stripe), Primer `bgColor-muted`, Polaris `bg-surface-secondary`, AG Grid the "chrome" colour (2% of the text colour mixed into the background), Glide `#F7F7F8` on white (1.07:1), USWDS `base-lighter`, Lightning a header background token.
- **No fill**: GOV.UK, Material (the surface colour), Fluent, Spectrum (transparent; a fill only when the body scrolls under it), daisyUI, shadcn/ui.
- **Weight**: semibold or bold in Carbon, Primer, GOV.UK, daisyUI (600), AG Grid (500 in Quartz, 700 in Alpine, bold in Balham). daisyUI also lowers the header's text to `base-content/60`; AG Grid's Balham to 60% of the text colour.
- **Sticky**: NN/g, "Freeze header rows and header columns (if the table is larger than the screen)". daisyUI's `table-pin-rows` makes `thead` and `tfoot` sticky and gives them a `base-100` fill, which a sticky header needs so that rows do not show through. USWDS has a sticky-header variant.
- **A sorted column**: USWDS gives the sorted column's header and cells their own fill. Carbon and Primer show the sort icon only; Carbon shows the icon of an unsorted column on hover.

**The filter row.** No design system read documents a filter row under the header as a pattern of its own. AG Grid's "floating filters" are a second row inside the header area and share the header's background (**Recalled**; not read in source). **Inferred**: the header row and the filter row form one group and should look like one: the same fill or none for both, no rule between them, and the one stronger rule under the group where the body begins. Few's use of rules is exactly this: to separate "the headers and footers from the body".

**Inferred** for a sticky header in a grid with keyboard focus: a cell scrolled under a sticky header may not be "entirely hidden" when it receives focus (WCAG 2.4.11, [Understanding](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html), which names sticky headers as the typical cause and scroll padding as the remedy).

## 5. Cell states

- **Editable against read-only.** Lightning is the only system read that documents it: an editable cell shows a fill and an edit (pencil) button when its row is hovered or the cell is focused, and a locked cell shows a lock icon in the same place ([inline-edit](https://github.com/salesforce-ux/design-system/blob/master/ui/components/data-tables/inline-edit/_index.scss)). AG Grid, MUI and Glide show nothing at rest (**Recalled** for MUI and Glide). Airtable marks computed fields in the column header, not in every cell (**Recalled**). Atlassian advises against inline inputs in a table altogether for complex cases. **Inferred**: nothing at rest; the signal belongs on hover and on focus, or once per column in the header, not in every cell. A table in which every editable cell looks like an input at rest is a form, and the reading tasks suffer.
- **A cell being edited.** AG Grid: a border in the accent colour and a card shadow on the cell. Lightning: the cell fill plus the inset ring. Ours keeps the focus ring. **Inferred**: enough, provided the ring has the contrast.
- **An edited cell not yet saved.** Lightning: a highlight fill (`$color-background-highlight`). AG Grid has a batch-edit fill. Not relevant to us while every cell saves by itself.
- **A failed cell.** Lightning: the highlight fill *and* a thick inset border in the error colour. AG Grid: `invalidColor` (`#e02525`) for the editor, and a row fill of 25% of it for full-row editing. Atlassian: "highlight the affected row with an error icon". WCAG 1.4.1 names "error is shown in red" as the example of what is not enough by itself ([Understanding 1.4.1](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)). **Inferred**: colour plus a mark that is a shape (an icon, or a corner mark in the spreadsheet tradition), plus the message we already have.
- **A saving cell.** No system read prescribes one. Ours is `opacity-60`. **Computed**: 4.5:1 in the Phoenix light theme, 4.48:1 on a `base-200` stripe. WCAG exempts components "not available for user interaction" from contrast, and a cell that is saving is arguably that for a moment, but the value in it is still being read. **Inferred**: `opacity-70` is 6.2:1 or more and costs nothing.
- **A value that is not available.** No system read prescribes a treatment. **Inferred**: a placeholder in muted text must still reach 4.5:1 (1.4.3 applies to it as to any text), must not be an empty cell (which reads as "empty value"), and must have a text alternative.
- **Numbers.** GOV.UK: "align the numbers to the right in table cells", with tabular numerals in the numeric cell. Primer: right alignment "for numbers and other data that is best represented right-aligned". USWDS right-aligns in its examples. Tailwind: `tabular-nums`.
- **Truncation.** Apple: "an ellipsis in the middle of text can make an item easier to distinguish because it preserves both the beginning and the end". Lightning fades truncated text and repeats the fade in the hover colour, a reminder that a truncation gradient has to follow the row's fill; a plain ellipsis (ours) has no such dependency.

## 6. Nested tables

**What the systems do.**

- **AG Grid master/detail** ([_grid-layout.css](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/core/css/_grid-layout.css), [styling docs](https://www.ag-grid.com/javascript-data-grid/theming-master-detail/), [nesting docs](https://www.ag-grid.com/javascript-data-grid/master-detail-nesting/)): the detail is a full-width row with the data background and a padding of `spacing * 3.75`, 30 px at the default, on all four sides. Inside sits a complete grid: its own wrapper border with rounded corners, its own header with the header fill, its own rows. So the beginning and end are marked three times: by the inset, by the enclosing border, and by the repeated header. Nesting deeper is allowed with "no special configuration" and repeats the same. A comment in the stylesheet notes that "a nested grid must not inherit the highlight of the row hosting it". The docs' own example of restyling the detail row uses a tint and a left padding of 40 px.
- **Carbon expandable rows** ([_data-table-expandable.scss](https://github.com/carbon-design-system/carbon/blob/main/packages/styles/scss/components/data-table/expandable/_data-table-expandable.scss)): the expanded row has the *same* fill as the parent, an inline-start padding of 3.5 rem, and a bottom border. Parent and child highlight together on hover, in either direction. With zebra, parent and child share one stripe. Carbon describes the content as "supplementary information"; it does not show a table inside a table.
- **Polaris** `IndexTable`: "Rows of type 'child' are indented", and a "subheader" row "looks and behaves the same as the table header" ([docs source](https://github.com/Shopify/polaris/blob/main/polaris.shopify.com/content/components/tables/index-table.mdx)).
- **Spectrum**: section-header rows and summary rows carry a fill one step stronger (`gray-200`) and bold text.
- **MUI X**: a detail panel under the row, of arbitrary content, 500 px high by default ([master-detail docs](https://github.com/mui/mui-x/blob/master/docs/data/data-grid/master-detail/master-detail.md)). Its look is left to the content.
- **shadcn/ui**: a row containing an expanded control is tinted (`has-aria-expanded:bg-muted/50`).
- **Notion sub-items**: nested in a toggle and indented; the alternative, a flattened list, is described as "sub-items won't be indented in the list to distinguish them from parent items" ([Notion help](https://www.notion.com/help/tasks-and-dependencies)). Sub-items have the parent's columns.
- **Airtable**: related records are not shown inside the row. A record opens as a view of its own, and linked records appear there as a list or grid ([record detail layout](https://support.airtable.com/docs/en/airtable-interface-layout-record-detail)).
- **Fluent 2, Material, GOV.UK, USWDS**: no expandable-row pattern in the table component (for Fluent and Material: none found in the source read; not searched exhaustively).

**What that adds up to**, **Inferred**:

- Every system that puts content inside a row uses indentation or an inset. None relies on a fill alone, and Carbon deliberately uses no fill at all.
- The only one that shows a *full table of another shape* inside a row is AG Grid, and its answer is enclosure (a bordered box) plus a repeated header. Enclosure is Few's case too: a boundary around a table is justified exactly when another table is close by.
- Sub-rows of the *same* shape (Notion, Polaris, tree grids) are a different problem: there, indentation of the first column is the only cue available, because the columns continue. It does not carry over to a table of a different shape.

**Without indentation, the minimal set that marks the beginning and the end:**

1. **Beginning: the open parent row stays marked.** The expander already turns. Give the open row the hover fill for as long as it is open (shadcn/ui's rule, and Carbon's parent-and-child hover). It says "what follows belongs to this row" without moving anything.
2. **Beginning: the nested table's own header row.** A header row in the middle of a table is the strongest "another table starts here" signal there is, and it is already there. It works only if the header looks like a header, which is an argument for a header fill or a clear rule under it (see [question 4](#4-header-and-filter-row)).
3. **End: one stronger rule under the region.** A bottom border two or three times the strength of a row line (not thicker, or by 1 px at most) under the last row of the detail body, closing the region the way a rule closes a table's footer. Each level closes itself, so three levels deep needs no extra design: three regions end with three rules.
4. Nothing else. No fill for the region, no inset, no left rule, no card.

Why a rule and not a fill, **Inferred**:

- A fill per level needs three distinguishable tints. `base-100`, `base-200` and `base-300` are 1.05 to 1.33:1 apart; that is not three reliably different levels, and a host theme may make them closer.
- Forced-colors mode replaces every background with the system's and keeps borders ([MDN, forced-colors](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/forced-colors)). A region marked by a fill has no mark there.
- A fill competes with the hover, the stripe and a future selection for the same narrow range of greys.

If the rule alone proves too weak in the prototype, the next step that still moves nothing is a **rule along the inline-start edge of the region** (2 px, drawn as a border on the detail cells, in the strong line colour). It is the "left rule" of the question, without indentation. It is decoration in the owner's sense, so it is the fallback, not the recommendation.

**Does striping the parent help or hurt?** **Inferred**: it hurts. An expanded region interrupts the rhythm that is the stripe's whole function; the stripe after the region may or may not continue the count (Carbon had to write rules for it; SAP switched striping off for trees); and a striped nested table inside a striped parent produces bands of two tables that cannot be told apart by fill. If striping is on, the stripe should count records (parent rows), the detail body should stay unstriped, and each nested table should start its own count.

## 7. Row actions and status values

- **Row actions.** Primer: a single action goes in the last column under a visually hidden header; several go into a menu; "Do not pull out more than 1 action." Atlassian: put edit and delete in a "more actions" menu, and give each row's control a unique name ("Edit component 3"). Fluent shows row actions on hover and on focus within the row (in its source the actions cell becomes opaque on `:hover` and `:focus-within`).
- **Destructive actions.** Not read in a table-specific source. The general convention (Carbon's danger button, Polaris's critical tone, daisyUI's `btn-error`) is the error colour on the destructive control only, and a confirmation (**Recalled**). **Computed**: `text-error` on `base-100` is 4.3:1, 2.9:1, 2.9:1 and 5.5:1 in the four themes, so red *text* on the row is not reliably readable; a filled `btn-error` with `error-content`, or red only in the menu item and the confirm button, is.
- **Status and enum values.** Carbon's status indicator pattern: "Relying solely on color to convey status is insufficient, especially for users with color vision deficiencies", with colour, shape and symbol to be combined, and in data tables the icon left-aligned with its text ([pattern](https://carbondesignsystem.com/patterns/status-indicator-pattern/)). Polaris rows can carry a `tone` (subdued, success, warning, critical) as a whole-row fill. NN/g describes indicators as contextual and passive and shows colour paired with a shape (a green arrow up, a red arrow down). WCAG 1.4.1 allows colour coding "if it is complemented by other visual indication". **Inferred**: a badge whose *text* is the value, with colour as reinforcement; never a coloured dot alone; and at most four or five tones, since more cannot be told apart or remembered.
- **Booleans.** No system read prescribes a treatment. **Inferred**: a check mark or a checkbox against an empty or dash state, which differ in shape; not green against red.
- **No empirical study** of badges against plain text in tables was found.

## 8. Tokens and theming

**How the systems structure it.**

- **AG Grid**: three inputs, `backgroundColor`, `foregroundColor`, `accentColor`, and everything else is a mix of them that can be overridden one by one. Read in source: border = 15% foreground; chrome and header = 2% foreground; row hover = 8% accent; selected row = 12% accent; range selection = 20% accent; odd row = the data background; invalid = `#e02525`. The dark scheme changes the inputs and three of the mixes. ([shared-css.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-stack/src/theming/shared/shared-css.ts), [core-css.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/core/core-css.ts), [color-schemes.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/parts/theme/color-schemes.ts))
- **Carbon**: role tokens per state that resolve per theme: `$layer`, `$layer-accent` (header and stripe), `$layer-hover`, `$layer-selected`, `$layer-selected-hover`, `$border-subtle`, `$focus`, `$text-primary`, `$text-secondary`. The `layer` tokens come in three sets so that a table on a raised surface steps up with it ([style](https://carbondesignsystem.com/components/data-table/style/)).
- **Bootstrap**: one "emphasis" colour at 5% (stripe), 7.5% (hover) and 10% (active).
- **MUI X**: hover and selected are a colour and an opacity taken from the application's theme.
- **Glide**: a flat theme object (`bgCell`, `bgHeader`, `bgHeaderHovered`, `accentColor`, `accentLight`, `borderColor`, `horizontalBorderColor`, `textDark`, `textMedium`, `textLight`), which can be overridden per row and per cell.
- **daisyUI**: no table tokens. The table uses `base-100`, `base-200`, `base-300` and mixes of `base-content`. Semantic colours come in pairs with a `-content` colour that "must have clear contrast" with it. `base-200` is "a darker base shade that gives elevation", in dark themes too.
- **Tailwind 4**: theme variables are CSS custom properties; a utility can take one directly (`bg-(--my-colour)`), and `color-mix()` works in arbitrary values ([theme docs](https://tailwindcss.com/docs/theme)).

**Mapping onto daisyUI**, **Inferred**. The roles a table needs and where each can come from, without the library naming a colour:

| Role | Source in daisyUI terms | Why |
| --- | --- | --- |
| surface | `base-100`, or transparent | the host's page colour |
| text | `base-content` | the paired content colour |
| muted text (header, placeholder) | `base-content` at 60 to 70% | 5.2:1 or more in the four themes |
| row line | `base-content` at about 10% | what daisyUI does at 5%, at a visible strength |
| strong line (under the header group, end of a nested region) | `base-content` at 20 to 30% | 1.6 to 2.3:1 |
| stripe | `base-content` at about 5% | 1.12 to 1.14:1, the range of Bootstrap and USWDS |
| hover, open row | `base-content` at about 10% | one step above the stripe |
| selected (later) | `primary` at 10 to 12% | AG Grid's and Material's rule: accent, not grey |
| header fill (optional) | the stripe value, or `base-200` | Carbon uses one token for both |
| focus ring | `base-content` | the only colour guaranteed to contrast with the base |
| invalid | `error` for the ring and icon; never for text on the base | see the computed table |

Mixing `base-content` into the base, as against using `base-200` and `base-300`, has three properties that matter here: the result is a known distance from the base in any theme; it goes *toward the text colour*, so it is darker in light themes and lighter in dark ones, which is the direction dark themes use for raised surfaces (Material's dark theme guidance, **Recalled**); and it can be translucent, so it lies over a stripe or a parent's fill without a rule for every combination.

**Inferred**, how a host would theme it: the table defines its roles as custom properties on its root element with the defaults above (for example `--ash-table-line`, `--ash-table-stripe`, `--ash-table-hover`, `--ash-table-focus`), and uses them through utilities. A host changes its daisyUI theme and the table follows; a host that wants a different table sets a property in its own CSS. A nested table inherits the properties through the DOM, so it looks the same as its parent without any code, which is the owner's rule.

**Options the systems expose**, read in their documentation:

| Option | Who has it |
| --- | --- |
| striping on/off | Carbon, Polaris, Lightning, SAP, USWDS, daisyUI, Bootstrap, AG Grid, Apple |
| density / row height | Carbon (5 sizes), Fluent (3), Primer (3), Spectrum (4), daisyUI (5), USWDS (compact), SAP (cozy, compact, condensed; **Recalled**), AG Grid (`spacing`, `rowHeight`) |
| column lines on/off | Lightning, AG Grid, USWDS (borderless) |
| row lines on/off | AG Grid, USWDS (borderless) |
| sticky header | daisyUI, USWDS, Carbon (**Recalled**) |
| row hover on/off | Lightning (off switch), daisyUI (per row), Polaris `DataTable` |

No system exposes the *colours* as component options. They come from the theme.

## 9. Density and typography

- **Row heights.** Carbon: 24, 32, 40 (default), 48, 64 px. Fluent: 24, 34, 44 px (default). Primer: cell padding of 4, 8 (default) or 12 px. daisyUI: `table-xs` to `table-xl`, default `table-md` with 12 px vertical padding and 14 px text; `table-sm` and `table-xs` also shrink the text to 12 px and 11 px. Ours is daisyUI's default: about 44 px a row, at the roomy end.
- **Few's limits**: vertical white space between rows of 20% of the text height made a twelve-column table "somewhat difficult to track"; white space equal to the text height is "the practical limit" beyond which the table stops reading as a table.
- **Why striping matters more when dense**, **Inferred** from Few and from Enders' second study: the aid is needed when white space cannot separate the rows, that is, in compact tables and in wide ones. At our default density, with a hover, the case for stripes is at its weakest. A compact density is where a striping option earns its place.
- **Focus appearance and density.** A ring inside the cell takes 2 px of every side. In a 24 px row that is a sixth of the height; padding has to allow for it.
- **Text size.** WCAG 1.4.12 asks that content survives a line height of 1.5 and wider letter and word spacing set by the user ([Understanding 1.4.12](https://www.w3.org/WAI/WCAG22/Understanding/text-spacing.html), **Recalled**, not fetched). A row of fixed height that truncates to one line is the classic way to fail it. Data tables are exempt from reflow (1.4.10) because they "rely on two-dimensional layout for understanding"; the controls around them are not ([Understanding 1.4.10](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html)).

## Comparison

Design systems and libraries. "Text %" means that share of the text colour mixed into the background. Sources as in the sections above; cells marked (R) are **Recalled**.

| | Striping: default / option | Stripe contrast | Hover | Selected | Focus | Row lines | Header | Nested / expanded |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Carbon | off / yes | 1.20 to 1.32 | always; `$layer-hover` | fill + checkbox | 2 px inset, `$focus` | horizontal; none when striped | fill (= stripe token), semibold (R) | same fill, 3.5 rem indent, bottom border, hover as one |
| Fluent 2 | off / no | n/a | subtle fill | brand or neutral fill + checkbox | 2 px outline on the row | horizontal | no fill | none found |
| Material 2 web | off / no | n/a | text 4% | `primary` 4% + checkbox | not read | horizontal, text 12% | no fill | none found |
| Atlassian | off / none found | n/a | highlight (R) | "never rely on highlighted rows" | not read | not read | not read | none found |
| Polaris IndexTable | off / yes | not computed | fill | fill + checkbox | not read | horizontal | fill | child rows indented; subheader rows look like the header |
| Primer | off / no | n/a | transparent hover fill | none | not read | horizontal, outer border | fill, semibold | row groups (not read in detail) |
| Spectrum | off / no | n/a | text at low opacity | accent at low opacity | focus-indicator token | horizontal | none unless scrolling | section and summary rows: stronger fill, bold |
| Lightning | off / yes | = hover colour | on, can be turned off | fill | focused cell: 1 px inset + fill | optional; column lines optional | fill | tree grid (not read) |
| SAP UI5 | off / yes | not read | yes (R) | yes (R) | not read | grid lines (R) | not read | striping unavailable in tree mode |
| GOV.UK | off / no | n/a | none | n/a | n/a | horizontal | bold, no fill | n/a |
| USWDS | off / yes | 1.14 (R for the hex) | none | n/a | n/a | all four sides; borderless variant | fill | n/a |
| Apple macOS | on in the bordered style / yes | system | n/a | persistent highlight | system | n/a | system | outline views with disclosure |
| daisyUI 5 | off / yes | 1.05 to 1.17 | opt-in per row | docs: `base-200` | none | horizontal, text 5% | no fill, 600, text 60% | none |
| Bootstrap 5 | off / yes | 1.12 | opt-in, 7.5% | 10% | n/a | horizontal | no fill | none |
| AG Grid Quartz | off / yes | n/a | accent 8% | accent 12% | 1 px accent border on the cell | horizontal, text 15%; outer border | text 2% fill, weight 500 | 30 px padding, bordered detail grid, own header |
| AG Grid Balham | on | about 1.02 | accent 8% | accent 12% | focus shadow | horizontal, text 20%; header column lines | fill, bold, text 60% | as Quartz |
| MUI X Data Grid | off / by class | app's | theme hover opacity | `primary` at selected opacity | 1 px `primary` outline, inset | horizontal; outer border | optional fill | detail panel, free content |
| Glide Data Grid | off / per-row theme (R) | n/a | header hover only (rows: R) | accent 10% | accent ring (R) | both directions | `#F7F7F8`, 600 | row groups (R) |
| shadcn/ui table | off / no | n/a | `muted` 50% | `muted` | n/a | horizontal | medium weight, no fill | a row with an expanded control is tinted |

Products. Only the first two rows were read in a first-party source in this session; the rest is **Recalled** and should be checked against the products before anything is built on it.

| | Striping | Hover | Selected | Focus | Lines | Header | Nested |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Excel tables | on by default: "By default, banding is applied to the rows in a table to make the data easier to read." ([Microsoft](https://support.microsoft.com/en-us/Excel/apply-shading-to-alternate-rows-or-columns-in-a-worksheet)) | none | range fill | thick border on the active cell | full grid | style-dependent fill | outline groups in the margin |
| Notion databases | none | row fill | checkbox + fill | cell border | horizontal and vertical hairlines | muted text, no fill | sub-items: toggle and indentation ([Notion](https://www.notion.com/help/tasks-and-dependencies)) |
| Google Sheets | opt-in ("alternating colours", and in converted tables) | none | range fill | blue border on the active cell | full grid | none | row groups in the margin |
| Airtable grid | none | row fill | checkbox + fill | blue border on the active cell | full grid | faint fill | a record opens as its own view; linked records listed there |
| Linear lists | none | row fill | fill | row focus | none or faint horizontal | group headers with a fill | sub-issues indented |
| Stripe Dashboard | none | row fill | checkbox | n/a | horizontal hairlines | small muted text, no fill | a row opens a page |
| GitHub | none | row fill | n/a | n/a | horizontal hairlines, outer border | muted fill | a row opens a page |
| TanStack Table | headless: ships no styles; the examples are unstyled or plain bordered tables | | | | | | |

## Accessibility constraints

Each line is a constraint on colour, with its criterion. Level AA unless marked.

- [ ] **Colour is never the only carrier of a state** (1.4.1 Use of Color, level A). A failed cell, a selected row, a status value and a destructive action each need a second cue: an icon, a shape, text, a checkbox. A difference of 3:1 in *lightness* counts as more than colour, but not where the reader must recognise the particular colour. ([Understanding 1.4.1](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html))
- [ ] **All text reaches 4.5:1 on the background it is actually on** (1.4.3 Contrast (Minimum)). That includes text on a stripe, on a hover fill, on a selected fill, header text at reduced opacity, placeholders, and "text that is shown when a pointer is hovering over an object or when an object has keyboard focus". Disabled controls are exempt. ([Understanding 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html))
- [ ] **The focus indicator reaches 3:1 against the colours next to it** (1.4.11 Non-text Contrast, with 2.4.7 Focus Visible). "The visual focus indicator for a component must have sufficient contrast against the adjacent background when the component is focused." An inset ring is adjacent to the cell's own fill, so it must pass on the base, the stripe, the hover and the selected fill.
- [ ] **A mark that identifies a state reaches 3:1** (1.4.11): the ring or icon of a failed cell, the check in a checkbox, the triangle of an expander, a sort arrow.
- [ ] **The boundary of an input reaches 3:1 if the boundary is what shows that it is an input** (1.4.11). This applies to the filter row's inputs. A boundary is not required where text already identifies the control.
- [ ] **Stripes, hover fills and row lines have no minimum contrast.** The Understanding document says hover treatments "do not themselves need to contrast 3:1 against the background", and that colour changes between states of a component need not reach 3:1 "when they do not appear next to each other". It does not mention table rows, stripes or separators at all. **Inferred**: a stripe conveys no information the table's structure does not already carry, so it is decoration under 1.4.11; the limit on it is from the other side, the text contrast on it. A stripe that is invisible to a reader with low contrast sensitivity fails nobody, it merely does not help them; lines do.
- [ ] **A state's fill must not take contrast away.** "The key consideration for any hover effect is that it does not cause a component itself to lose sufficient contrast against adjacent colors." A ring that passes on the base and fails on the hover fill fails.
- [ ] **A focused cell is not hidden under a sticky header or footer** (2.4.11 Focus Not Obscured (Minimum)). Scroll padding is the documented remedy.
- [ ] **Focus appearance** (2.4.13, level AAA): an indicator at least as large as a 2 px perimeter, with 3:1 between the same pixels focused and unfocused. The Understanding document says the smallest indicator that qualifies is "a solid line that appears inside the component against the component's outer edge", and that one inset further "would need to be at least 3px thick". Ours (`outline-2` with an offset of -2 px) is that smallest case, by my reading; its colour is what fails. ([Understanding 2.4.13](https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html))
- [ ] **One ring colour for every background**: WCAG technique C40, a two-colour indicator, exists because "it can be easy to miss some components" when ring colours are chosen per background ([C40](https://www.w3.org/WAI/WCAG22/Techniques/css/C40)). A ring in the text colour is the one-colour equivalent on a surface that is always the base.
- [ ] **Forced colours** (Windows High Contrast; no criterion of its own, but 1.4.1, 1.4.11 and 2.4.7 still have to hold there). `background-color`, `border-color`, `outline-color` and `color` are replaced by system colours; `box-shadow` is "forced to 'none'". So fills vanish (stripes, hover, selection, tints of any kind), borders and outlines stay, and anything drawn as a shadow, including Tailwind's `ring` and `inset-ring` utilities, is gone. Fluent's table shows the remedy: the selected row carries a `2px solid transparent` border, which becomes visible in forced colours, and its hover uses the system `Highlight` colour. MDN: do not build a separate design, make "small tweaks". ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/forced-colors), [Tailwind box-shadow](https://tailwindcss.com/docs/box-shadow))
- [ ] **`prefers-contrast: more`** is the place to strengthen row lines and to switch a muted header to full text colour; `custom` matches forced colours ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-contrast)).
- [ ] **`prefers-reduced-motion`**: concerns "scaling or panning large objects"; a change of colour or opacity is the documented replacement, not a problem. The turning expander triangle is small. Row-fill transitions should still be instant or very short, for the flicker reason in question 3. ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion))
- [ ] **Hover is not available on touch.** Carbon puts hover styles behind `@media (any-hover: hover)` and MUI resets them under `@media (hover: none)`, so that a tap does not leave a row looking hovered. Nothing may depend on hover alone (2.1.1, and 1.4.13 for content that appears on hover; **Recalled**, not fetched).
- [ ] **Status colours for colour-blind readers.** Red against green is the pair to avoid; AG Grid's accessibility page says "care should be taken when using colours to provide information" and demonstrates with a simulator. The safeguard is the same as for 1.4.1: text or shape with every colour.
- [ ] **Dark themes.** The same ratios apply. Shadows do not read on dark surfaces, so separation comes from lines and lightness (**Recalled**, Material dark theme guidance). daisyUI's `base-200` and `base-300` are *darker* than `base-100` in dark themes, so a `base-200` stripe or header is a recess there, not a raised band.
- [ ] **Text spacing and reflow** (1.4.12, 1.4.10): see question 9.

## What this suggests for ash_table

Recommendations for the owner to decide, in the order I would take them. None is a decision. Each names what it rests on.

### Fix now, independent of theming

1. **Draw the focus ring in `base-content`, not `primary`.** *Computed*: `primary` is 2.75:1 (light) and 2.90:1 (dark) on `base-100` in the default Phoenix themes; 1.4.11 asks 3:1; `base-content` is 12.6:1 or more in every theme checked and is the one colour daisyUI promises will contrast with the base. Keep the ring as it is otherwise (2 px, flush inside the cell). If the brand colour is wanted in the ring, the alternative is a two-colour ring (technique C40), which costs a second declaration.
2. **Give a failed cell a mark that is not a colour, and one that survives forced colours.** *Computed and read*: `error` against `primary` is 1.01:1 in the dark theme, so the failed ring and the focus ring differ by hue alone (1.4.1); and `inset-ring` is a box shadow, which forced-colors mode removes. Lightning uses a thick inset border plus a fill plus an icon; Atlassian an icon. Suggested: keep the `error` ring, draw it as an outline or border so that it survives, and add a small mark in the cell's corner or an icon before the value. The message popover stays.
3. **Raise a saving cell from `opacity-60` to `opacity-70`.** *Computed*: 4.5:1 today in the Phoenix light theme and 4.48:1 on a `base-200` stripe; 6.2:1 or more at 70%.
4. **Check the filter inputs' border against 1.4.11** (not computed here: daisyUI's input border colour was not read).

### The default: what the table looks like with no configuration

5. **No stripes.** *Evidence and prescription*: no consistent gain at this density (Enders 1), a loss in one search study (Lee), and the default of every design system read. Preference alone favours stripes (31% first) but lines are close (20%) and equally unobjectionable (4% last for both).
6. **Horizontal lines only, a little stronger than daisyUI's.** *Prescription*: the common default. *Computed*: daisyUI's 5% line is 1.12:1, the faintest of all systems read; about 10% (1.25 to 1.30:1) is still a hairline. No vertical lines.
7. **A row hover, behind `@media (hover: hover)`, with no transition.** *Prescription*: Carbon "should always be enabled", NN/g, and it is what Enders' participants did by hand. About 10% of `base-content`. This is a change from today's "no hover"; it is the cheapest tracking aid and it does not conflict with anything else in the table.
8. **The header and the filter row as one group**: semibold labels in `base-content` at 60 to 70% as daisyUI has them (5.2:1 or more), no rule between the two rows, one strong rule (20 to 30% of `base-content`) under the group. A faint header fill is optional; half the systems have one. *Inferred* from Few's use of rules and from AG Grid's floating filters; no system documents a filter row.
9. **Editable and read-only cells look the same at rest.** A read-only cell says so on focus (it already does to a screen reader). If a visual cue is wanted, Lightning's is the documented one: a pencil or a lock on hover and focus. Not a fill per cell.
10. **Numbers right-aligned with `tabular-nums`** (GOV.UK, Primer, USWDS), if not already done by the column types.
11. **Derive every tint from `base-content` mixed into the base, and the ring from `base-content`; use `primary` only for a future selection and `error` only for the failed mark.** Define them as custom properties on the table's root so that a host theme changes the table and a host can override one value in CSS. *Prescription*: AG Grid's, Bootstrap's and daisyUI's own approach. *Computed*: `base-200` and `base-300` are 1.05 to 1.33:1 from the base depending on the theme and go the wrong way in dark themes.

### Where a nested table begins and ends, without indentation

12. **Three things, all of which move nothing:**
    - the **open parent row keeps the hover fill** while it is open;
    - the **nested table's header row looks like a header** (which recommendation 8 gives it), so that a header in mid-table reads as "a table starts here";
    - **one strong rule under the last row of the detail region**, in the same colour as the rule under a header group.

    *Read*: AG Grid marks its detail grid by an inset, a border and a repeated header; Carbon by an indent and a bottom border; shadcn/ui tints the row that holds an expanded control. Indentation and inset are out by the owner's rule; the repeated header, the bottom border and the tinted parent remain. *Inferred*: rules rather than a fill for the region, because fills disappear in forced colours, three levels of fill cannot be told apart in these themes, and a fill would compete with hover and stripe. Each level closes with its own rule, so depth needs no further design.

    The fallback, if the prototype shows the end is still missed: a 2 px rule along the inline-start edge of the detail region. It takes no room from the content and survives forced colours, but it is decoration, so it is second choice.

### Options worth exposing

13. **`striped`**, default off. For compact and wide tables, where the evidence for it is strongest. About 5% of `base-content` (1.12 to 1.14:1; Bootstrap and USWDS are there, Few says no more is needed). It must count records, not `<tbody>` elements; it must leave detail regions unstriped; a nested table counts for itself; row lines go when stripes come (Carbon). It cannot be daisyUI's `table-zebra` with our markup.
14. **Density**, three steps, default as today. daisyUI's `table-sm` and `table-xs` exist but also shrink the text to 12 px and 11 px; a compact step that keeps 14 px text and reduces only padding is the better reading of Carbon's and Primer's scales.
15. **Column lines**, default off, for tables that are mostly edited. Lightning, AG Grid and USWDS have the switch; the spreadsheet products have them always.
16. **A sticky header**, default off, with scroll padding so that a focused cell is never under it (2.4.11).
17. **Nothing for colours.** They come from the theme and, where a host insists, from the custom properties. No system exposes them as component options.

### Later, with the features that need them

18. **Selection**: a tint of `primary` at 10 to 12% *and* a checkbox, with `aria-selected`; a transparent border on the selected row so that it shows in forced colours (Fluent).
19. **Status and enum values**: a daisyUI badge whose text is the value, tone as reinforcement, few tones; booleans by shape.
20. **Destructive row actions**: `error` on the destructive control and in the confirm button only; not red text on the row (*computed*: below 4.5:1 in three of four themes).

### What not to do

- Not `primary` for anything that has to be seen: it is a brand colour and may be any lightness.
- Not `base-200` and `base-300` as "one step" and "two steps": the steps are not the same size in any two themes.
- Not a fill to mark a nested region, and not a different fill per level.
- Not stripes and row lines together, and not stripes on a table that has open nested tables unless the stripe counts records.
- Not two-colour or multi-row stripes: 15% and 28% ranked them last (Enders 3).
- Not a state shown by a shadow alone (`ring`, `inset-ring`, `shadow`): it is gone in forced colours.
- Not a state shown by colour alone.
- Not a slow transition on row fills.
- Not an input look on every editable cell at rest.

## What could not be verified or reached

- **Material Design 3**: `m3.material.io` does not render for the fetcher. That M3 has no data table specification is from a web search and from memory, not from the site. The Material values above are from the Material 2 web component's source.
- **Fluent 2, Lightning 2, Spectrum, Apple and SAP documentation sites**: not rendered or refused (404, 403, script-only). Read instead: Fluent's, Lightning 1's, Spectrum CSS's and OpenUI5's source, and Apple's documentation through its JSON endpoint. SAP's written guidance on when to use alternate row colours was not read; only the property and its default.
- **Atlassian**: the usage page was read; the component's stylesheet was not, so its hover and header are recalled.
- **Carbon's status indicator pattern**: the summary returned both "at least three" and "at least two" of colour, shape and symbol; the exact rule should be checked on the page before it is quoted.
- **Lee 2014**: the thesis abstract was read. The proceedings paper (Lee, Kent, Carswell, Seidelman and Sublette, HFES 2014) was refused (403) and is known from a search result only.
- **Enders**: the two articles were read in full. The "peer-reviewed paper" the first article mentions was not located. The study's table images and the exact grey of the stripe were not read.
- **Few**: read in a copy of chapter 8 hosted by a university, not in the book. Page numbers are from that copy.
- **Products** (Airtable, Notion apart from sub-items, Linear, Google Sheets, Stripe, GitHub's pages, Glide's row behaviour): described from memory. None was opened in a browser in this session. Google's own help page on alternating colours was not found; that it is opt-in is from third-party tutorials.
- **Baymard**: nothing relevant was found; not searched in depth.
- **Any later empirical study** of striping, of row lines against white space, of hover, or of nested tables: two searches found only Enders and Lee. There may be more in the HCI literature (for instance on table lenses or on reading tabular data with eye tracking); none was found.
- **The contrast figures** are computed from the themes' OKLCH values converted to sRGB, and from mixes computed in OKLab; daisyUI mixes in OKLCH, which differs slightly for chromatic colours. They were not measured in a browser. Differences of 0.1 around a threshold (the saving cell at 4.5:1) should be measured before they are relied on.
- **daisyUI's input border colour**, and with it whether the filter inputs meet 1.4.11, was not read.
- **`:nth-child(... of S)`** is stated as supported by all current browsers from memory; check the support table before building on it.
- **Carbon's transition duration** (70 ms) and its header weight, AG Grid's floating filter styling, MUI's detail panel look, and Material's dark theme guidance are recalled, not read.

## Sources

Evidence and expert guidance:

- Jessica Enders, [Zebra Striping: Does it Really Help?](https://alistapart.com/article/zebrastripingdoesithelp/), A List Apart, 2008.
- Jessica Enders, [Zebra Striping: More Data for the Case](https://alistapart.com/article/zebrastripingmoredataforthecase/), A List Apart, 2008.
- Michael P. Lee, [The Effects of Alternate-Line Shading on Visual Search in Grid-Based Graphic Designs](https://uknowledge.uky.edu/psychology_etds/51), MS thesis, University of Kentucky, 2014.
- Nielsen Norman Group, [Data Tables: Four Major User Tasks](https://www.nngroup.com/articles/data-tables/); [Indicators, Validations, and Notifications](https://www.nngroup.com/articles/indicators-validations-notifications/).
- Stephen Few, *Show Me the Numbers*, 2nd edition, 2012, chapter 8, "Table Design" ([copy read](https://fenix.iseg.ulisboa.pt/downloadFile/1407508027555973/Few_2012_Chpt-8.pdf)).

Accessibility:

- W3C, Understanding WCAG 2.2: [1.4.1](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html), [1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), [1.4.10](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html), [1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html), [2.4.7](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html), [2.4.11](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html), [2.4.13](https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html); technique [C40](https://www.w3.org/WAI/WCAG22/Techniques/css/C40).
- W3C, ARIA Authoring Practices, [Grid pattern](https://www.w3.org/WAI/ARIA/apg/patterns/grid/).
- MDN: [forced-colors](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/forced-colors), [prefers-contrast](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-contrast), [prefers-reduced-motion](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion).

Design systems and libraries (documentation and source):

- daisyUI 5: [table component](https://daisyui.com/components/table/), [table.css](https://github.com/saadeghi/daisyui/blob/master/packages/daisyui/src/components/table.css), [light.css](https://github.com/saadeghi/daisyui/blob/master/packages/daisyui/src/themes/light.css), [dark.css](https://github.com/saadeghi/daisyui/blob/master/packages/daisyui/src/themes/dark.css), [llms.txt](https://daisyui.com/llms.txt).
- Phoenix 1.8 installer: [app.css.eex](https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_assets/app.css.eex).
- Tailwind CSS 4: [states](https://tailwindcss.com/docs/hover-focus-and-other-states), [theme variables](https://tailwindcss.com/docs/theme), [box-shadow](https://tailwindcss.com/docs/box-shadow), [font-variant-numeric](https://tailwindcss.com/docs/font-variant-numeric).
- IBM Carbon: [usage](https://carbondesignsystem.com/components/data-table/usage/), [style](https://carbondesignsystem.com/components/data-table/style/), [accessibility](https://carbondesignsystem.com/components/data-table/accessibility/), [status indicator pattern](https://carbondesignsystem.com/patterns/status-indicator-pattern/), [_data-table.scss](https://github.com/carbon-design-system/carbon/blob/main/packages/styles/scss/components/data-table/_data-table.scss), [_data-table-expandable.scss](https://github.com/carbon-design-system/carbon/blob/main/packages/styles/scss/components/data-table/expandable/_data-table-expandable.scss), [themes.json](https://github.com/carbon-design-system/carbon/blob/main/packages/themes/src/dtcg/themes.json), [colors.json](https://github.com/carbon-design-system/carbon/blob/main/packages/colors/src/dtcg/colors.json).
- Microsoft Fluent UI v9: [useTableRowStyles](https://github.com/microsoft/fluentui/blob/master/packages/react-components/react-table/library/src/components/TableRow/useTableRowStyles.styles.ts), [useTableCellStyles](https://github.com/microsoft/fluentui/blob/master/packages/react-components/react-table/library/src/components/TableCell/useTableCellStyles.styles.ts), [useDataGridRowStyles](https://github.com/microsoft/fluentui/blob/master/packages/react-components/react-table/library/src/components/DataGridRow/useDataGridRowStyles.styles.ts).
- Material Components Web: [_data-table-theme.scss](https://github.com/material-components/material-components-web/blob/master/packages/mdc-data-table/_data-table-theme.scss).
- Atlassian: [dynamic table, usage](https://atlassian.design/components/dynamic-table/usage).
- Shopify Polaris: [IndexTable.module.css](https://github.com/Shopify/polaris/blob/main/polaris-react/src/components/IndexTable/IndexTable.module.css), [index-table.mdx](https://github.com/Shopify/polaris/blob/main/polaris.shopify.com/content/components/tables/index-table.mdx), [DataTable.module.css](https://github.com/Shopify/polaris/blob/main/polaris-react/src/components/DataTable/DataTable.module.css).
- GitHub Primer: [DataTable](https://primer.style/product/components/data-table/), [Table.module.css](https://github.com/primer/react/blob/main/packages/react/src/DataTable/Table.module.css).
- Adobe Spectrum CSS: [table/index.css](https://github.com/adobe/spectrum-css/blob/main/components/table/index.css).
- Salesforce Lightning Design System: [data-tables/base](https://github.com/salesforce-ux/design-system/blob/master/ui/components/data-tables/base/_index.scss), [data-tables/inline-edit](https://github.com/salesforce-ux/design-system/blob/master/ui/components/data-tables/inline-edit/_index.scss).
- SAP OpenUI5: [sap.ui.table.Table](https://github.com/SAP/openui5/blob/master/src/sap.ui.table/src/sap/ui/table/Table.js), [sap.m.Table](https://github.com/SAP/openui5/blob/master/src/sap.m/src/sap/m/Table.js).
- GOV.UK Design System: [table](https://design-system.service.gov.uk/components/table/), [_mixin.scss](https://github.com/alphagov/govuk-frontend/blob/main/packages/govuk-frontend/src/govuk/components/table/_mixin.scss).
- US Web Design System: [table](https://designsystem.digital.gov/components/table/), [table mixins](https://github.com/uswds/uswds/blob/develop/packages/uswds-core/src/styles/mixins/general/table.scss), [component settings](https://github.com/uswds/uswds/blob/develop/packages/uswds-core/src/styles/settings/_settings-components.scss).
- Apple: [Human Interface Guidelines, Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables), [`usesAlternatingRowBackgroundColors`](https://developer.apple.com/documentation/appkit/nstableview/usesalternatingrowbackgroundcolors), [`alternatingRowBackgrounds(_:)`](https://developer.apple.com/documentation/swiftui/view/alternatingrowbackgrounds(_:)).
- Bootstrap 5: [_variables.scss](https://github.com/twbs/bootstrap/blob/main/scss/_variables.scss).
- AG Grid: [core-css.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/core/core-css.ts), [shared-css.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-stack/src/theming/shared/shared-css.ts), [themes.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/parts/theme/themes.ts), [color-schemes.ts](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/parts/color-scheme/color-schemes.ts), [_grid-layout.css](https://github.com/ag-grid/ag-grid/blob/latest/packages/ag-grid-community/src/theming/core/css/_grid-layout.css), [master/detail styling](https://www.ag-grid.com/javascript-data-grid/theming-master-detail/), [master/detail nesting](https://www.ag-grid.com/javascript-data-grid/master-detail-nesting/), [colours](https://www.ag-grid.com/javascript-data-grid/theming-colors/), [borders](https://www.ag-grid.com/javascript-data-grid/theming-borders/), [accessibility](https://www.ag-grid.com/javascript-data-grid/accessibility/).
- MUI X Data Grid: [GridRootStyles.ts](https://github.com/mui/mui-x/blob/master/packages/x-data-grid/src/components/containers/GridRootStyles.ts), [style docs](https://github.com/mui/mui-x/blob/master/docs/data/data-grid/style/style.md), [master-detail docs](https://github.com/mui/mui-x/blob/master/docs/data/data-grid/master-detail/master-detail.md).
- Glide Data Grid: [styles.ts](https://github.com/glideapps/glide-data-grid/blob/main/packages/core/src/common/styles.ts).
- shadcn/ui: [table.tsx](https://github.com/shadcn-ui/ui/blob/main/apps/v4/registry/new-york-v4/ui/table.tsx).

Products:

- Microsoft, [Apply shading to alternate rows or columns in a worksheet](https://support.microsoft.com/en-us/Excel/apply-shading-to-alternate-rows-or-columns-in-a-worksheet).
- Notion, [Sub-items and dependencies](https://www.notion.com/help/tasks-and-dependencies).
- Airtable, [Interface layout: Record detail](https://support.airtable.com/docs/en/airtable-interface-layout-record-detail).

Earlier research in this repository that this note builds on: `docs/research/state-of-the-art-data-grids.md` (branch `research/state-of-the-art-data-grids`), which covers behaviour; this note covers appearance.
