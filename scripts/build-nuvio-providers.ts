import { buildProviders } from '../src/nuvio-compat/nuvioBuilder.ts';
import * as path from 'path';
import * as fs from 'fs/promises';

async function run() {
    const providersDir = path.resolve('..', 'src/providers')
    const outDir = path.resolve('..', 'dist/nuvio-providers')

    try {
        await fs.mkdir(outDir, { recursive: true });
    } catch (e) {}

    await buildProviders(providersDir, outDir, {
      name: 'CinePro',
      version: '1.0.0',
      description: '',
    })
}

run().catch(console.error);
