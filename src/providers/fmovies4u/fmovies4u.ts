import { BaseProvider, type Subtitle, type SourceType } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source
} from '@omss/framework';
import { decrypt } from './decrypt.ts';
import type {
    ApiResponse,
    StreamUrl,
    Track as ApiTrack
} from './fmovies4u.types.ts';

export class Fmovies4U extends BaseProvider {
    readonly id = 'fmovies4u';
    readonly name = 'Fmovies4U';
    // disabled since fmovies4u is currently broken... the logic is probably the same later on
    readonly enabled = false;
    readonly BASE_URL = 'https://fmovies4u.com';
    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150 Safari/537.36',
        Accept: 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9',
        Referer: this.BASE_URL
    };

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies', 'tv']
    };

    /**
     * Fetch movie sources
     */
    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media, {
            type: 'movie'
        });
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
     * Shared movie/TV fetcher
     */
    private async getSources(
        media: ProviderMediaObject,
        params: { type: 'movie' | 'tv'; season?: string; episode?: string }
    ): Promise<ProviderResult> {
        try {
            const path =
                params.type === 'movie'
                    ? `/api/movie/${media.tmdbId}`
                    : `/api/tv/${media.tmdbId}/${params.season}/${params.episode}`;

            const request = await fetch(
                `${this.BASE_URL}${path}?_cb=${Date.now()}`,
                {
                    headers: {
                        ...this.HEADERS,
                        Referer: this.buildRefererUrl(media)
                    }
                }
            );

            const encryptedText = await request.text();
            if (!encryptedText) {
                return this.emptyResult(
                    'Failed to fetch encrypted sources',
                    media
                );
            }

            const decrypted: ApiResponse = decrypt(encryptedText);
            if (
                !decrypted?.success ||
                !Array.isArray(decrypted.sources) ||
                !decrypted.sources.length
            ) {
                return this.emptyResult('No sources returned from API', media);
            }

            return this.mapApiResponseToResult(decrypted, media);
        } catch (error) {
            return this.emptyResult('Failed to decrypt sources', media);
        }
    }

    /**
     * Map decrypted API response to OMSS ProviderResult
     */
    private mapApiResponseToResult(
        apiResponse: ApiResponse,
        media: ProviderMediaObject
    ): ProviderResult {
        const sources: Source[] = [];
        const subtitles: Subtitle[] = [];

        for (const apiSource of apiResponse.sources) {
            const streamUrls: StreamUrl[] = Array.isArray(apiSource.url)
                ? apiSource.url
                : [];

            for (const stream of streamUrls) {
                const type = (stream.type?.toLowerCase() ||
                    'hls') as SourceType;

                sources.push({
                    url: this.createProxyUrl(
                        stream.link,
                        stream.link.includes('file2')
                            ? {
                                  referer: 'https://videostr.net/',
                                  origin: 'https://videostr.net'
                              }
                            : {
                                  ...this.HEADERS,
                                  Referer: this.buildRefererUrl(media)
                              }
                    ),
                    type,
                    quality: stream.quality || 'Auto',
                    provider: {
                        id: this.id,
                        name: this.name
                    },
                    audioTracks: [
                        {
                            language: 'eng',
                            label: 'English'
                        }
                    ]
                });
            }

            if (Array.isArray(apiSource.tracks)) {
                for (const track of apiSource.tracks as ApiTrack[]) {
                    if (!track || typeof track !== 'object') continue;

                    const kind = (track.kind || track.type || '')
                        .toString()
                        .toLowerCase();
                    const isSubtitle =
                        kind === 'subtitles' ||
                        kind === 'subtitle' ||
                        kind === 'captions' ||
                        typeof track.file === 'string';

                    if (!isSubtitle) continue;

                    const url = track.file || track.url;
                    if (!url || typeof url !== 'string') continue;

                    const label =
                        track.label ||
                        track.srclang ||
                        track.lang ||
                        track.language ||
                        'Unknown subtitle';

                    const ext = (url.split('.').pop() || '').toLowerCase();
                    let format: Subtitle['format'] = 'vtt';
                    if (ext === 'srt') format = 'srt';
                    else if (ext === 'ass') format = 'ass';
                    else if (ext === 'ssa') format = 'ssa';
                    else if (ext === 'ttml' || ext === 'xml') format = 'ttml';

                    subtitles.push({
                        url: this.createProxyUrl(url),
                        label,
                        format
                    });
                }
            }
        }

        return {
            sources,
            subtitles,
            diagnostics: []
        };
    }

    /**
     * Build correct referer URL for given server number
     * @param media media object
     */
    private buildRefererUrl(media: ProviderMediaObject): string {
        return media.type === 'movie'
            ? `${this.BASE_URL}/embed/movie/${media.tmdbId}?autoPlay=false`
            : `${this.BASE_URL}/embed/tv/${media.tmdbId}/${media.s}/${media.e}?autoPlay=false`;
    }

    /**
     * Return empty result with diagnostic
     */
    private emptyResult(
        message: string,
        media: ProviderMediaObject
    ): ProviderResult {
        // @ts-ignore
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
