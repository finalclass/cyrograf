import { defineConfig } from "@vscode/test-cli";

export default defineConfig({
  files: "out/src/test/**/*.test.js",
  workspaceFolder: "test-fixture",
  version: process.env.CYROGRAF_VSCODE_VERSION ?? "1.95.3",
  launchArgs: [
    "--disable-gpu",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-workspace-trust",
  ],
  mocha: {
    timeout: 60000,
  },
});