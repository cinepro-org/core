import { BaseProvider, type Subtitle, type SourceType } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source
} from '@omss/framework';
import type { StreamResponse } from './vidzee.types.ts';
import { decrypt, deriveKey } from './decrypt.ts';

export class VidZeeProvider extends BaseProvider {
    readonly id = 'vidzee';
    readonly name = 'VidZee';
    readonly enabled = true;
    readonly BASE_URL = 'https://core.vidzee.wtf';
    readonly PLAYER_URL = 'https://player.vidzee.wtf';
    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (X11; Ubuntu; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.7051.98 Safari/537.36',
        Accept: 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9',
        Referer: this.PLAYER_URL,
        Origin: this.PLAYER_URL
    };

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies', 'tv']
    };

    /**
     * Fetch movie sources
     */
    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media, { type: 'movie' });
    }

    /**
     * Fetch TV episode sources
     */
    async getTVSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media, {
            type: 'tv',
            season: media.s?.toString(),
            episode: media.e?.toString()
        });
    }

    /**
     * Main scraping logic - Parallel servers + FULL parallel decryption
     */
    private async getSources(
        media: ProviderMediaObject,
        params: { type: 'movie' | 'tv'; season?: string; episode?: string }
    ): Promise<ProviderResult> {
        try {
            const tmdbId = media.tmdbId;

            const decKey = await this.fetchDecryptionKey();
            if (!decKey) {
                return this.emptyResult(
                    'Failed to fetch decryption key',
                    media
                );
            }

            const serverPromises = Array.from({ length: 14 }, (_, serverId) =>
                this.fetchServer(tmdbId, serverId, params)
            );

            const results = await Promise.allSettled(serverPromises);
            const successfulResponses: StreamResponse[] = [];

            for (const result of results) {
                if (result.status === 'fulfilled' && result.value) {
                    successfulResponses.push(result.value);
                }
            }

            if (successfulResponses.length === 0) {
                return this.emptyResult('No working servers', media);
            }

            const decryptPromises = successfulResponses.map((response) =>
                Promise.all(
                    response.url.map((u) => decrypt(u.link, decKey))
                ).then((decryptedLinks) => ({
                    response,
                    decryptedLinks
                }))
            );
            const decryptionResults = await Promise.all(decryptPromises);

            const allDecryptedLinks: string[] = [];
            const allSubtitles = new Map<string, Subtitle>();

            for (const { response, decryptedLinks } of decryptionResults) {
                allDecryptedLinks.push(...decryptedLinks);

                for (const track of response.tracks) {
                    if (track.url && track.lang) {
                        const proxySubUrl = this.createProxyUrl(
                            track.url,
                            this.HEADERS
                        );
                        const subKey = `${track.lang}_${response.serverInfo.number}`;

                        if (!allSubtitles.has(subKey)) {
                            allSubtitles.set(subKey, {
                                url: proxySubUrl,
                                label: track.lang.replace(/\d+/g, '').trim(),
                                format: 'vtt'
                            });
                        }
                    }
                }
            }

            const uniqueLinks = [...new Set(allDecryptedLinks)].filter(
                (link) => link && link.startsWith('http')
            );

            const sources: Source[] = uniqueLinks.map((link) => ({
                url: this.createProxyUrl(
                    link,
                    link.includes('fast33lane')
                        ? {
                              referer: 'https://rapidairmax.site/',
                              origin: 'https://rapidairmax.site'
                          }
                        : link.includes('serversicuro.cc')
                          ? {}
                          : {
                                ...this.HEADERS,
                                Referer: `${this.BASE_URL}/`
                            }
                ),
                type: 'hls' as SourceType,
                quality: this.inferQuality(link),
                audioTracks: [
                    link.includes('phim1280.tv')
                        ? {
                              language: 'vie',
                              label: 'Vietnamese'
                          }
                        : {
                              language: 'eng',
                              label: 'English'
                          }
                ],
                provider: {
                    id: this.id,
                    name: this.name
                }
            }));

            return {
                sources,
                subtitles: Array.from(allSubtitles.values()),
                diagnostics: []
            };
        } catch (error) {
            return this.emptyResult(
                error instanceof Error ? error.message : 'Unknown error',
                media
            );
        }
    }

    /**
     * Fetch single server response
     */
    private async fetchServer(
        tmdbId: string,
        serverId: number,
        params: { type: 'movie' | 'tv'; season?: string; episode?: string }
    ): Promise<StreamResponse | null> {
        try {
            let url =
                this.PLAYER_URL + `/api/server?id=${tmdbId}&sr=${serverId}`;

            if (params.type === 'tv' && params.season && params.episode) {
                url += `&ss=${params.season}&ep=${params.episode}`;
            }

            const response = await fetch(url, {
                headers: this.HEADERS
            });

            if (!response.ok) {
                return null;
            }

            return (await response.json()) as StreamResponse;
        } catch {
            return null;
        }
    }

    private async fetchDecryptionKey(): Promise<string | null> {
        try {
            const response = await fetch(`${this.BASE_URL}/api-key`, {
                headers: this.HEADERS
            });

            if (response.status === 200) {
                const data = await response.text();
                if (data) {
                    return await deriveKey(data);
                }
            }

            return null;
        } catch {
            return null;
        }
    }

    /**
     * Return empty result with diagnostic
     */
    private emptyResult(
        message: string,
        media: ProviderMediaObject
    ): ProviderResult {
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

    /**
     * Health check
     */
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
