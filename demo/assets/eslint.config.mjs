// ESLint for the demo's React islands and its page JS, for the code-quality
// gate (`mix check` in demo; docs/research/code-quality-tools.md in the
// root). ESLint 9, not 10: eslint-plugin-jsx-a11y's peer range ends at 9.
import js from "@eslint/js"
import tseslint from "typescript-eslint"
import reactHooks from "eslint-plugin-react-hooks"
import jsxA11y from "eslint-plugin-jsx-a11y"
import globals from "globals"

export default tseslint.config(
  {ignores: ["vendor/**", "node_modules/**"]},
  js.configs.recommended,
  tseslint.configs.recommended,
  reactHooks.configs.flat.recommended,
  jsxA11y.flatConfigs.recommended,
  {languageOptions: {globals: {...globals.browser}}},
)
