// The look of the React kit's controls: shadcn/ui's (`../ui/`), with the
// focus ring every control of a table has (stage 8a, the tab-model note):
// the outline of 2 pixels in the text colour, as daisyUI draws its own,
// the one colour a theme promises to be seen on its background. The
// structure of the table and its states are drawn by the kit's style sheet
// (`assets/css/react_kit.css`), by the table's markers.
import {buttonVariants} from "../ui/button"
import {badgeVariants} from "../ui/badge"
import {cn} from "../lib/utils"

const RING = "focus-visible:ring-0 focus-visible:border-transparent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-current"

type Variant = "default" | "outline" | "ghost" | "destructive" | "secondary" | "link"

// a button of the table: shadcn's, small, or extra small in a row
export function button(variant: Variant, size: "sm" | "xs", ...extra: (string | false | null | undefined)[]) {
  return cn(buttonVariants({variant, size: "sm"}), RING, size === "xs" && "h-6 gap-1 rounded px-2 text-xs", ...extra)
}

export function badge(...extra: string[]) {
  return cn(badgeVariants({variant: "outline"}), "align-top", ...extra)
}

// shadcn's Input and the native select drawn as one, at the size of a row
const FIELD = "h-7 rounded-md border border-input bg-transparent px-2 text-xs shadow-xs outline-none focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-current aria-invalid:border-destructive"

export const input = (...extra: string[]) => cn(FIELD, ...extra)
export const select = (...extra: string[]) => cn(FIELD, "pe-6", ...extra)

// shadcn's Checkbox drawn on the native box (no Radix: the hook paints it)
export const box = (...extra: string[]) =>
  cn("size-4 shrink-0 rounded-[4px] border border-input accent-current focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-current", ...extra)
