import * as fs from 'fs/promises'
import * as path from 'path'
import { BaseProvider } from '@omss/framework';
import { fileURLToPath } from 'url'
import esbuild from 'esbuild'
import type { BuildOptions } from 'esbuild';
import {quickJsModuleExportCompatPlugin, removeBlankImportsPlugin} from './esbuildPlugins.ts'
// @ts-ignore
import browserifyBuiltins from 'browserify/lib/builtins.js'

interface BuildProvider {
  id: string;
  name: string;
  className: string;
  filePath: string;
  instance: BaseProvider;
}

interface BuildProviderConfig {
  name: string;
  version: string;
  description: string;
}

interface NuvioScraper {
  id: string
  name: string
  description: string
  version: string
  hasSettings?: boolean
  author?: string
  supportedTypes: Array<string>
  filename: string
  enabled: boolean
  formats: Array<string>
  logo: string
  contentLanguage: Array<string>
}

interface NuvioManifest {
  name?: string
  version?: string
  description?: string
  scrapers: Array<NuvioScraper>
}

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const PROVIDERS_DIR = 'providers';

const define: any = {}
for (const key in process.env) {
  if (key.startsWith('NODE_') || key === 'TMDB_API_KEY') {
    continue
  }
  define[`process.env.${key}`] = JSON.stringify(process.env[key])
}

define['process.env.NODE_ENV'] = JSON.stringify(process.env.NODE_ENV || 'production')
// Never expose the private TMDB API key by default.
//define['process.env.TMDB_API_KEY'] = JSON.stringify('')
define['process.env.TMDB_API_KEY'] = JSON.stringify(process.env.TMDB_API_KEY)
define['process.env.NUVIO_ENV'] = JSON.stringify(true)

function generatePlaceholder(nuvioWrapperTemplate: string, className: string, providerPath: string): string {
  const frameworkPath = path.resolve(__dirname, '..', '..', 'node_modules/@omss/framework/dist').replace(/\\/g, '/')
  return nuvioWrapperTemplate
    .replace(/__FRAMEWORK_PATH__/g, frameworkPath)
    .replace(/__CLASS_NAME__/g, className)
    .replace(/__PROVIDER_PATH__/g, providerPath)
}

export async function buildProviders(providersDirectory: string, outDir: string, config: BuildProviderConfig, instances: BaseProvider[]|null = null) {
  // Empty the directory before building.
  await fs.rm(outDir, {
    force: true,
    recursive: true,
  })
  await fs.mkdir(outDir, {recursive: true})
  const files = await fs.readdir(providersDirectory, {recursive: true})
  const providers : BuildProvider[] = []

  for (const file of files) {
    if (file.endsWith('.ts') && !file.endsWith('.types.ts') && !file.endsWith('.test.ts')) {
      const filePath = path.join(providersDirectory, file)
      const stat = await fs.stat(filePath)
      if (stat.isDirectory()) {
        // Ignore directories
        continue
      }
      // Pick up providers that can be initialized
      const module = await import(filePath);
      for (const [name, ExportedClass] of Object.entries(module)) {
        if (typeof ExportedClass === 'function' && ExportedClass.prototype) {
          if (BaseProvider.prototype.isPrototypeOf(ExportedClass.prototype)) {
            try {
              let instance: BaseProvider|undefined;
              // Look up the instance from the already initialized version
              instance = instances?.find(i => i.constructor.name == name)
              if (!instance) {
                // Check if ExportedClass is a constructable class
                // @ts-ignore
                instance = new ExportedClass();
              }
              providers.push({
                id: instance!!.id,
                name: instance!!.name,
                className: name,
                filePath,
                instance: instance!!,
              })
            }
            catch (err) {
              console.warn(`[ProviderRegistry] Failed to instantiate ${name} from ${filePath}:`, err);
            }
          }
        }
      }
    }
  }

  console.log(`Found ${providers.length} providers to build. Output directory: ${outDir}`)

  config.description = config.description || 'A Nuvio provider for the cinepro providers.'
  const manifest: NuvioManifest = {
    name: config.name,
    version: config.version,
    description: config.description,
    scrapers: [],
  }
  const minifiedManifest: NuvioManifest = {
    name: `${config.name} (minified)`,
    version: config.version,
    description: config.description,
    scrapers: [],
  }

  const minOutDir = path.join(outDir, 'min')

  for (const provider of providers) {
    // Build minified and non-minified scripts.
    await buildProvider(provider, outDir, {minify: false}, manifest, config)
    await buildProvider(provider, minOutDir, {minify: true}, minifiedManifest, config)
  }

  await fs.writeFile(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2))
  await fs.writeFile(path.join(minOutDir, 'manifest.json'), JSON.stringify(minifiedManifest, null, 2))
}

let nuvioWrapperTemplate: string

function buildNuvioScraperDefinition(provider: BaseProvider, providerName: string, config: BuildProviderConfig): NuvioScraper {
  let hostname = new URL(provider.BASE_URL).hostname;
  const hostnameParts = hostname.split('.');
  if (hostnameParts.length > 2) {
    // Only pick the top-most level domain.
    hostname = hostnameParts.slice(hostnameParts.length - 2, hostnameParts.length).join('.');
  }
  let contentLanguage = (provider as any).contentLanguage || ['en'];
  if (!Array.isArray(contentLanguage)) {
    contentLanguage = [contentLanguage]
  }
  const result: NuvioScraper = {
    id: provider.id,
    name: provider.name,
    description: (provider as any).description || `The ${provider.id} Cinepro provider.`,
    version: (provider as any).version || config.version,
    author: (provider as any).author || 'cinepro',
    supportedTypes: (provider?.capabilities?.supportedContentTypes || ['movie', 'tv']).map(type => {
      if (type === 'movies') {
        return 'movie';
      }
      return type;
    }),
    filename: `${PROVIDERS_DIR}/${providerName}`,
    enabled: Boolean(provider.enabled),
    formats: ['mkv', 'mp4'],
    logo: (provider as any).logo ||`https://www.google.com/s2/favicons?domain=${hostname}&sz=128`,
    contentLanguage,
  };
  if ((provider as any).hasSettings) {
    result.hasSettings = true;
  }
  return result
}

async function buildProvider(provider: BuildProvider, outDir: string, options: any = {}, manifest: NuvioManifest, config: BuildProviderConfig) {
  let minify = options.minify || false;
  const {id, name, className, filePath, instance} = provider
  const providerName = `${id}${minify ? '.min' : ''}.js`
  const outFile = path.join(outDir, PROVIDERS_DIR, providerName)

  if (!nuvioWrapperTemplate) {
    nuvioWrapperTemplate = await fs.readFile(path.join(__dirname, 'nuvioWrapper.template.ts'), {encoding: 'utf8'})
  }

  // Since we use stdin, we can't easily use relative imports, so we have to use absolute paths in the import
  // since esbuild handles it during bundling anyway.
  const absoluteProviderPath = path.resolve(filePath).replace(/\\/g, '/')
  const wrapperCode = await generatePlaceholder(nuvioWrapperTemplate, className, absoluteProviderPath)

  try {
    const sourcePath = path.relative(path.resolve(__dirname, '..', '..'), filePath)
    const inject = []
    const esbuildConfig: BuildOptions = {
      stdin: {
        contents: wrapperCode,
        resolveDir: path.dirname(filePath),
        sourcefile: `wrapper-${id}.ts`,
        loader: 'ts',
      },
      bundle: true,
      outfile: outFile,
      format: 'cjs',
      platform: 'browser',
      mainFields: ['module', 'main'],
      target: 'es2016',
      minify,
      define,
      sourcemap: false,
      external: [
        // Modules that the Nuvio app provides - never attempt to bundle these.
        'cheerio-without-node-native',
        'react-native-cheerio',
        'cheerio',
        'crypto-js',
        'axios',
        'crypto',
      ],
      plugins: [
        removeBlankImportsPlugin(),
        //quickJsModuleExportCompatPlugin(),
      ],
      banner: {
        js: `/**\n * ${name} - Built from ${sourcePath}\n * Generated: ${new Date().toISOString()}\n */`
      },
      logLevel: 'warning'
    };
    if (process.env.NUVIO_NODEJS_COMPAT === 'true') {
      // Attempt to add as much NodeJS compatibility as possible.
      // Set this to true if your Nuvio client is running via QuickJS.
      esbuildConfig.alias = {
        // 'crypto' might not be available. So use a 'crypto-js' based shim.
        //'crypto': path.resolve(__dirname, 'shim', 'crypto-shim.js'),
        //'crypto': 'crypto-browserify',
        // Use browserify to automatically handle all this.
        // https://github.com/feross/buffer
        //'buffer': path.resolve(__dirname, 'shim', 'buffer-shim.js'),
        ...browserifyBuiltins,
      }
      // Replace global references.
      inject.push(
        path.resolve(__dirname, 'esbuildInjects.ts'),
      )
      esbuildConfig.inject = inject
    }
    await esbuild.build(esbuildConfig)

    // Add the scraper to the manifest.
    const scraper = buildNuvioScraperDefinition(instance, providerName, config)
    manifest.scrapers.push(scraper)

    const stats = await fs.stat(outFile)
    const sizeKB = (stats.size / 1024).toFixed(1)
    const minifyIndicator = options.minify ? ' (minified)' : ''
    console.log(`✅ ${providerName} (${sizeKB} KB)${minifyIndicator}`)
    return true
  } catch (err: any) {
    console.error(`❌ Failed to build ${id}:`, err.message)
    return false
  }
}
