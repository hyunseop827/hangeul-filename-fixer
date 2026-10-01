// Starts the Vite dev server, then Electron pointed at it. Closing Electron stops Vite.
// Run through `npm run dev:electron`, which compiles electron/ first.
import { spawn } from "node:child_process";
import electronPath from "electron";
import { createServer } from "vite";

const server = await createServer();
await server.listen();

const rendererUrl = server.resolvedUrls?.local[0];
if (!rendererUrl) {
  await server.close();
  throw new Error("Vite did not report a local URL.");
}

const electron = spawn(electronPath, ["."], {
  stdio: "inherit",
  env: { ...process.env, ELECTRON_RENDERER_URL: rendererUrl }
});

electron.on("exit", async (code, signal) => {
  await server.close();
  if (code === null) {
    console.error(`Electron exited with signal ${signal}`);
    process.exit(1);
  }
  process.exit(code);
});

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(signal, () => electron.kill(signal));
}
