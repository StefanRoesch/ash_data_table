import type { Locator } from "@playwright/test"

// Contrast as WCAG 2 defines it, measured on what the browser shows: a
// colour is not the value its style names but that value painted over
// everything behind it, at the opacity of every element around it. The
// browser does that painting here itself, on a canvas, so a colour in any
// notation (oklch, a colour mix, one with an alpha) comes out as the red,
// green and blue of the screen.

export type RGB = [number, number, number]

/** What of an element is measured: its text, its outline or its border. */
export type Paint = "text" | "outline" | "border"

/** The element itself, or one of the two boxes its style can add to it. */
export type Pseudo = "::before" | "::after"

/**
 * The colour an element's text, outline or border has on the screen, and the
 * colour behind it: the element's own background over those of everything
 * around it. An element in the top layer (an open dialog, an open popover)
 * has nothing of the page behind it that counts: its own background covers it.
 */
export async function shown(
  locator: Locator,
  paint: Paint,
  pseudo?: Pseudo,
): Promise<{ colour: RGB; behind: RGB }> {
  return locator.evaluate(
    (element, [paint, pseudo]) => {
      const canvas = document.createElement("canvas")
      canvas.width = canvas.height = 1
      const context = canvas.getContext("2d", { willReadFrequently: true })!

      // one colour painted over an opaque one
      const over = (under: number[], colour: string): number[] => {
        context.fillStyle = `rgb(${under.join(",")})`
        context.fillRect(0, 0, 1, 1)
        context.fillStyle = colour
        context.fillRect(0, 0, 1, 1)
        return Array.from(context.getImageData(0, 0, 1, 1).data.slice(0, 3))
      }
      const mixed = (under: number[], top: number[], opacity: number): number[] =>
        under.map((value, index) => Math.round(value + (top[index] - value) * opacity))

      let around: Element[] = []
      for (let node: Element | null = element; node; node = node.parentElement) around.unshift(node)
      const topLayer = around.findLastIndex((node) => node.matches("dialog[open], :popover-open"))
      if (topLayer > 0) around = around.slice(topLayer)

      // What is seen where `last` is painted inside the innermost element:
      // each element paints its background on what is behind it, then what
      // is in it, and its opacity lets what is behind it show through.
      const seen = (last: string | null): number[] => {
        const paintFrom = (index: number, backdrop: number[]): number[] => {
          const style = getComputedStyle(around[index])
          const own = over(backdrop, style.backgroundColor)
          const inner =
            index < around.length - 1 ? paintFrom(index + 1, own) : last ? over(own, last) : own
          const opacity = Number(style.opacity)
          return opacity < 1 ? mixed(backdrop, inner, opacity) : inner
        }
        return paintFrom(0, [255, 255, 255])
      }

      const style = getComputedStyle(element, pseudo)
      const colour = { text: style.color, outline: style.outlineColor, border: style.borderTopColor }[
        paint
      ]
      return { colour: seen(colour) as RGB, behind: seen(null) as RGB }
    },
    [paint, pseudo ?? null] as const,
  )
}

/** The contrast ratio of two colours: from 1, for the same colour, to 21, for black on white. */
export function contrast(one: RGB, other: RGB): number {
  const luminance = ([red, green, blue]: RGB): number => {
    const linear = (value: number): number => {
      const share = value / 255
      return share <= 0.04045 ? share / 12.92 : ((share + 0.055) / 1.055) ** 2.4
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }
  const [lighter, darker] = [luminance(one), luminance(other)].sort((a, b) => b - a)
  return (lighter + 0.05) / (darker + 0.05)
}

/** The contrast of an element's text, outline or border against what is behind it. */
export async function contrastOf(locator: Locator, paint: Paint, pseudo?: Pseudo): Promise<number> {
  const { colour, behind } = await shown(locator, paint, pseudo)
  return contrast(colour, behind)
}
