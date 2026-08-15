// Template file to use for nuvio addons.
import { BaseProvider, ProviderResult, Source } from '@omss/framework'
// @ts-expect-error
import { TMDBService } from '__FRAMEWORK_PATH__/services/tmdb.service.js'
// @ts-expect-error
import { __CLASS_NAME__ } from '__PROVIDER_PATH__'

if (typeof Response === 'undefined') {
  class Response {
    error() { return new Response() }
    redirect() { return new Response() }
    json() { return {} }
  }
  if (typeof global !== 'undefined') {
    // @ts-ignore
    global.Response = Response
  } else if (typeof globalThis !== 'undefined') {
    // @ts-ignore
    globalThis.Response = Response
  }
}

interface NuvioStreamSubtitle {
  url?: string
  language?: string
  name?: string
  headers?: object
}

interface NuvioStreamAudioTrack {
  name: string
  url: string
  language?: string
  headers?: object
}

interface NuvioStreamResult {
  title: string
  name?: string
  url: string
  quality?: string
  size?: string
  language?: string
  provider?: string
  type?: string
  seeders?: number
  peers?: number
  infoHash?: string
  headers?: object
  subtitles: NuvioStreamSubtitle[]
  audioTracks?: NuvioStreamAudioTrack[]
}

interface NuvioSetting {
  key: string
  type: 'header' | 'info' | 'text' | 'select' | 'toggle'
  label: string
  description?: string
  options?: {
    label: string
    value: string
  }[]
  defaultValue?: string | boolean
  isPassword?: boolean
  placeholder?: string
}

// Use a null cache service since we don't need caching, and the original cache services will have
// intervals which will stop the self-contained script from terminating.
class NullCacheService {
  constructor() {}
  async get(key: string) { return null }
  async set(key: string, value: any, ttl: number = 7200) { return null }
  async delete(key: string) {}
  async clear() {}
  cleanup() {}
  destroy() {}
}

// Use the user defined TMDB API key if defined.
let tmdbApiKey = process.env.TMDB_API_KEY
if (typeof globalThis !== 'undefined' && (globalThis as any).TMDB_API_KEY) {
  tmdbApiKey = (globalThis as any).TMDB_API_KEY
}
const tmdbService = new TMDBService(tmdbApiKey, new NullCacheService())
const instance: BaseProvider = new __CLASS_NAME__()

function unproxySource(source: any): any {
  if (!source || !source.url) {
    return null;
  }
  let url = new URL(source.url)
  let headers = {
    ...(source as any).headers,
  }
  if (url.pathname === '/v1/proxy') {
    const data = JSON.parse(url.searchParams.get('data') || '{}')
    url = new URL(data.url)
    headers = {
      ...data.headers,
      ...headers,
    }
  }
  return {
    ...source,
    url: url.toString(),
    headers,
  }
}
async function getStreams(tmdbId: string, mediaType: string, season: string, episode: string) {
  if (mediaType !== 'movie' && !season && !episode) {
    console.error(`Received a ${mediaType} without a season (${season}) and episode (${episode})`);
    return [];
  }
  // Get the full source info from the TMDB service.
  const source = await tmdbService.getMediaObject(mediaType, tmdbId, parseInt(String(season), 10), parseInt(String(episode), 10))
  let results
  if (mediaType === 'movie') {
    results = instance.getMovieSources(source)
  } else {
    results = instance.getTVSources(source)
  }

  return results.then((result: ProviderResult) => {
    // Remove the proxy portion of the source and subtitles since the provider will be
    // executed on the local device.
    const subtitles = result.subtitles.map((subtitle): NuvioStreamSubtitle => {
      return {
        url: subtitle.url,
        language: (subtitle as any).language || 'en',
        name: subtitle.label,
        headers: (subtitle as any).headers,
      }
    });
    // Log diagnostics if any.
    result.diagnostics.forEach(diagnostic => {
      let logFunction = (console as any)[diagnostic.severity];
      if (typeof logFunction !== 'function') {
        logFunction = console.log.bind(console, `{${diagnostic.severity}}`);
      }
      logFunction(`[${instance.name}]: [${diagnostic.code}] ${diagnostic.message}`)
    });
    return result.sources
      .map(unproxySource)
      .map((source: Source): NuvioStreamResult => {
        // Pick up audio tracks on the source or provider result level.
        const audioTracks = (source.audioTracks || (result as any).audioTracks || []).map(unproxySource).filter(Boolean);

        return {
          title: `${instance.name} - ${(source as any).title || source.quality}`,
          url: source.url,
          type: source.type,
          quality: source.quality,
          headers: (source as any).headers,
          provider: source.provider?.name,
          subtitles,
          audioTracks,
        }
      })
  })
}

async function onSettings() : Promise<NuvioSetting[]> {
  // https://github.com/paregi12/nuvio-providers/blob/main/DOCUMENTATION.md#provider-settings
  if (typeof (instance as any).getSettings === 'function') {
    return (instance as any).getSettings()
  }
  return []
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { getStreams, onSettings };
} else if (typeof globalThis !== 'undefined') {
  // @ts-ignore
  globalThis.getStreams = getStreams;
  // @ts-ignore
  globalThis.onSettings = onSettings;
} else if (typeof global !== 'undefined') {
  // For React Native environment
  // @ts-ignore
  global.__CLASS_NAME__Module = { getStreams, onSettings };
}
