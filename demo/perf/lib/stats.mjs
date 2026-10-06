export function median(values) {
  const sorted = values.filter((value) => value !== null && value !== undefined).sort((a, b) => a - b)
  if (sorted.length === 0) return null
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

export const min = (values) => (values.length ? Math.min(...values) : null)
export const max = (values) => (values.length ? Math.max(...values) : null)

/** Median, least and greatest of one field over the repetitions. */
export function summary(repetitions, field) {
  const values = repetitions.map((repetition) => repetition[field]).filter((v) => typeof v === "number")
  return { median: median(values), min: min(values), max: max(values), n: values.length }
}
