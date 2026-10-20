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
  // `process.env.NODE_ENV` is replaced by esbuild's `--define` (config/config.exs).
  {languageOptions: {globals: {...globals.browser, process: "readonly"}}},
  {
    rules: {
      // a name that starts with `_` is unused on purpose
      "@typescript-eslint/no-unused-vars": ["error", {argsIgnorePattern: "^_", varsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_"}],
      // usePart(name) reads the part from context: no component is made during render.
      "react-hooks/static-components": "off",
      // role="cell" on a td is on purpose: the grid is role=table and mirrors the HEEx kit's markup.
      "jsx-a11y/no-interactive-element-to-noninteractive-role": "off",
      // role="rowgroup" on a tbody is on purpose, as the HEEx kit draws it.
      "jsx-a11y/no-redundant-roles": "off",
    },
  },
)
