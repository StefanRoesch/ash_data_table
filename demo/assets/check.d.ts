// For the type check only (tsconfig.check.json): the Hex esbuild replaces
// `process.env.NODE_ENV` (`--define`, config/config.exs); there is no Node.
declare const process: {env: {NODE_ENV?: string}}
