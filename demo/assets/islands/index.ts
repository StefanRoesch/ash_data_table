// The React components live_react may render, by the name a page gives
// `<.react name="…">` (app.js hands them to `getHooks`).
//
// The folder is `islands/`, not `react/`: assets/tsconfig.json has
// `baseUrl: "."`, which esbuild honours, so a folder named `react` would
// shadow the `react` package.
import {Sample} from "./Sample"

export default {Sample}
