import fs from 'fs/promises';
import path from 'path';
import browserify from 'browserify';
import { Readable } from 'stream';
import { Plugin, PluginBuild } from 'esbuild';

/**
 * esbuild plugin that runs Browserify over emitted JS chunks
 * to improve compatibility with quickjs.
 *
 * Useful for:
 * - CommonJS wrapping
 * - global polyfills
 * - older browser module compatibility
 *
 * Requires:
 *   npm install browserify
 */
export function browserifyPlugin(options: any = {}): Plugin {
  return {
    name: 'browserify',
    setup(build: PluginBuild) {
      build.onEnd(async (result) => {
        if (result.errors.length > 0) {
          return;
        }

        //const fs = await import('fs/promises');
        //const path = await import('path');

        const outdir = build.initialOptions.outdir;
        const outfile = build.initialOptions.outfile;

        const files = [];

        if (outfile) {
          files.push(outfile);
        }

        if (outdir) {
          const entries = await fs.readdir(outdir);

          for (const entry of entries) {
            if (entry.endsWith('.js')) {
              files.push(path.join(outdir, entry));
            }
          }
        }

        await Promise.all(
          files.map(async (file) => {
            const code = await fs.readFile(file, 'utf8');

            const bundled = await new Promise<String>((resolve, reject) => {
              const b = browserify({
                standalone: options.standalone,
                insertGlobalVars: {
                  global: () => 'globalThis',
                  ...options.insertGlobalVars,
                },
                detectGlobals: true,
                browserField: true,
              });

              const stream = Readable.from([code]);

              b.add(stream, {
                file,
              });

              b.bundle((err, buffer) => {
                if (err) {
                  reject(err);
                  return;
                }

                resolve(buffer.toString('utf8'));
              });
            });

            await fs.writeFile(file, bundled, 'utf8');
          })
        );
      });
    },
  };
}

export function removeBlankImportsPlugin(blankDependencies = [
  'fs/promises', 'url', 'path', 'url', 'stream',
  'ioredis', 'fastify', '@fastify',
]): Plugin {
  // Remove certain "require" dependencies referenced within @omss/framework that aren't necessary during
  // the runtime from the final bundle.
  const blankDependencyRegexp = new RegExp(`^(${blankDependencies.join('|')})\\/?(.+)?`, 'i')
  return {
    name: 'blankimport',
    setup(build: PluginBuild) {
      build.onResolve({filter: blankDependencyRegexp}, (args: any) => ({
        path: args.path,
        namespace: 'blankimport'
      }))
      build.onLoad({filter: blankDependencyRegexp, namespace: 'blankimport'}, async (args: any) => {
        const contents = JSON.stringify(
          /**
           * Operation steps:
           * - Import the module server side so you're 100% sure it will resolve
           * NOTE: A module won't get completely imported twice unless its import url changes, so the import is cached.
           * - get the keys of the import. This will get the name of every named export present in the built-in
           * - Reduce the string array into an object with the initializer {}, each string is added as the key of the object with an empty string
           *   so named imports will work but will just import a blank object.
           * - Finally stringify the object and let esbuild handle the rest for you
           */
          Object.keys(await import(args.path)).reduce<Object>((p, c) => ({...p, [c]: ''}), {})
        )
        return {
          contents,
          loader: 'json'
        }
      })
    }
  }
}

export function quickJsModuleExportCompatPlugin(): Plugin {
  return {
    name: 'quickjs-compat',
    setup(build: PluginBuild) {
      build.onEnd(async (result) => {
        if (result.outputFiles) {
          const promises = result.outputFiles.map(file => {
            let code = file.text;

            const replacement = `
if (typeof module !== 'undefined' && module.exports) {
  $0
} else {
  globalThis.$__default = $1
}`
            // Replace module.exports with a global assignment
            code = code.replace(
              /^module\.exports\s*=\s*(.+?)(?=\n|;|$)/,
              replacement
            );

            return fs.writeFile(file.path, code);
          });
          await Promise.all(promises);
        }
      });
    }
  }
}
