import { BaseProvider } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult
} from '@omss/framework';
import { generateRandomUserAgent } from '../../utils/ua.ts';
import type { TulnexApiResponse } from './tulnex.types.ts';
import { decryptPayload } from './decrypt.ts';
import { extractUrl } from './tulnex.mapper.ts';

export class TulnexProvider extends BaseProvider {
    readonly id = 'tulnex';
    readonly name = 'Tulnex';
    readonly enabled = true;

    readonly BASE_URL = 'https://api.tulnex.com';
    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'accept-language': 'en-US,en;q=0.9',
        'cache-control': 'no-cache'
    };

    readonly SERVERS = [
        `onion`,
        `vidzee`,
        `icefy`,
        `tik`,
        `vaplayer`,
        `vidfast-alpha`,
        `uniquestream`,
        `vidfast-mega`,
        `vidfast-vrapid`,
        `allmovies`,
        `vidlink`,
        `vidfast-vedge`,
        `vidfast-vfast`,
        `moviebox`
    ];

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies', 'tv']
    };

    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return await this.getSources(media);
    }

    async getTVSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return await this.getSources(media);
    }

    private async getSources(
        media: ProviderMediaObject
    ): Promise<ProviderResult> {
        try {
            const results = await Promise.allSettled(
                this.SERVERS.map((server) => this.doScrape(server, media))
            );

            const successful = results
                .filter(
                    (
                        r
                    ): r is PromiseFulfilledResult<
                        Awaited<ReturnType<typeof this.doScrape>>
                    > => r.status === 'fulfilled' && r.value != null
                )
                .map((r) => r.value);

            return {
                sources: successful
                    .filter((r) => r !== null)
                    .map((r) => ({
                        url: this.createProxyUrl(
                            r.url,
                            r.headers ? r.headers : {}
                        ),
                        type:
                            r.url.includes('mkv') || r.url.includes('mp4')
                                ? 'mp4'
                                : 'hls',
                        audioTracks: [
                            {
                                label: 'Original',
                                language: 'Original'
                            }
                        ],
                        quality: 'Auto',
                        provider: {
                            name: this.name,
                            id: this.id
                        }
                    })),
                subtitles: [],
                diagnostics: []
            };
        } catch (e) {
            return this.emptyResult(
                e instanceof Error ? e.message : 'Unknown provider error'
            );
        }
    }

    private async doScrape(serverName: string, media: ProviderMediaObject) {
        const url =
            media.type === 'movie'
                ? this.BASE_URL + '/' + serverName + '/movie/' + media.tmdbId
                : this.BASE_URL +
                  '/' +
                  serverName +
                  '/tv/' +
                  media.tmdbId +
                  '/' +
                  media.s +
                  '/' +
                  media.e;
        const req = await fetch(url, {
            headers: { ...this.HEADERS, Accept: 'application/json, */*' }
        });
        if (!req.ok) {
            return null;
        }
        const data = (await req.json()) as unknown as TulnexApiResponse;
        if (data.payload === undefined) {
            return null;
        }
        const decrypted = await decryptPayload(data.payload);
        if (!decrypted) {
            return null;
        }
        return extractUrl(decrypted);
    }

    private emptyResult(message: string): ProviderResult {
        return {
            sources: [],
            subtitles: [],
            diagnostics: [
                {
                    code: 'PROVIDER_ERROR',
                    message: `${this.name}: ${message}`,
                    field: '',
                    severity: 'error'
                }
            ]
        };
    }

    async healthCheck(): Promise<boolean> {
        try {
            const response = await fetch(this.BASE_URL, {
                method: 'HEAD',
                headers: this.HEADERS
            });
            return response.status === 200;
        } catch {
            return false;
        }
    }
}
