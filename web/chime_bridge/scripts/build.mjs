import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const chimeStatusShim = fileURLToPath(
  new URL('../src/chime-index-shim.ts', import.meta.url),
);

await build({
  entryPoints: ['src/index.ts'],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'es2020',
  outfile: 'dist/chime_web_bridge.js',
  legalComments: 'none',
  minify: true,
  plugins: [
    {
      name: 'chime-promote-status-import',
      setup(buildContext) {
        buildContext.onResolve({ filter: /^\.\.$/ }, args => {
          const importer = args.importer.replaceAll('\\', '/');
          if (importer.endsWith('/amazon-chime-sdk-js/build/task/PromoteToPrimaryMeetingTask.js')) {
            return { path: chimeStatusShim };
          }
          return null;
        });
      },
    },
  ],
});
