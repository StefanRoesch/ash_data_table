// The React components live_react may render, by the name a page gives
// `<.react name="…">` (app.js hands them to `getHooks`, through the React
// kit's `reactKitHooks`): the islands of the demo's React kit
// (`DemoWeb.ReactKit`, `table/`).
//
// The folder is `islands/`, not `react/`: assets/tsconfig.json has
// `baseUrl: "."`, which esbuild honours, so a folder named `react` would
// shadow the `react` package.
import {reactKit} from "./table"

export default reactKit()
