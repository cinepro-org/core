import type {
    Diagnostic,
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source,
    SubtitleFormat,
    SourceType,
    Subtitle
} from '@omss/framework';
import { BaseProvider } from '@omss/framework';
import { generateRandomUserAgent } from '../../utils/ua.ts';
import type { AnyEmbedApiResponse, TokenResponse } from './anyembed.types.ts';

// anyembed is still up and coming.
// their api is unstable and their sources return 403's and
// their own api returns pretty often a 500....
// for now we will keep this provider disabled until they stabilize their service a bit more.
// probably they'll change the logic, but for now we can keep the current implementation and just enable it once they fix their issues on their end.
export class AnyEmbed extends BaseProvider {
    readonly id = 'anyembed';
    readonly name = 'AnyEmbed';
    readonly enabled = false;
    readonly BASE_URL = 'https://api.anyembed.xyz';
    readonly FRONTEND_URL = 'https://anyembed.xyz';
    readonly HEADERS = {
        'User-Agent': '',
        accept: '*/*',
        referer: this.FRONTEND_URL,
        origin: this.FRONTEND_URL,
        'x-session-token': ''
    };

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies', 'tv']
    };

    /**
     * Fetch movie sources
     */
    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media);
    }

    /**
     * Fetch TV episode sources
     */
    async getTVSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media);
    }

    async getToken(): Promise<string> {
        const req = await fetch(this.BASE_URL + '/api/v1/session', {
            headers: this.HEADERS
        });
        const resp = (await req.json()) as TokenResponse;
        if (resp.token) {
            return resp.token;
        } else {
            throw 'no token found...';
        }
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

    /**
     * Main scraping logic
     */
    private async getSources(
        media: ProviderMediaObject
    ): Promise<ProviderResult> {
        try {
            this.HEADERS['User-Agent'] = generateRandomUserAgent();
            const session = await this.getToken();
            if (!session) {
                throw 'Failed to obtain session token';
            }
            this.HEADERS['x-session-token'] = session;

            const anyembedsources = await this.getApiResponse(media);

            // Map to ProviderResult
            return this.mapToProviderResult(anyembedsources);
        } catch (error) {
            return this.emptyResult(
                error instanceof Error
                    ? error.message
                    : 'Failed to process sources'
            );
        }
    }

    private async getApiResponse(
        media: ProviderMediaObject
    ): Promise<AnyEmbedApiResponse> {
        const url = `${this.BASE_URL}/api/v1/stream/${media.tmdbId}`;
        const response = await fetch(url, {
            headers: this.HEADERS
        });
        return (await response.json()) as AnyEmbedApiResponse;
    }

    private mapToProviderResult(
        apiResponse: AnyEmbedApiResponse
    ): ProviderResult {
        const diagnostics: Diagnostic[] = [];
        const subtitlesMap = new Map<string, Subtitle>();
        const sources: Source[] = [];

        const inferSourceType = (url: string): SourceType => {
            const cleanUrl = url.split('?')[0].toLowerCase();

            if (cleanUrl.endsWith('.m3u8')) return 'hls';
            if (cleanUrl.endsWith('.mpd')) return 'dash';
            if (cleanUrl.endsWith('.mp4')) return 'mp4';
            if (cleanUrl.endsWith('.mkv')) return 'mkv';
            if (cleanUrl.endsWith('.webm')) return 'webm';

            return 'hls';
        };

        const inferSubtitleFormat = (url: string): SubtitleFormat => {
            const cleanUrl = url.split('?')[0].toLowerCase();

            if (cleanUrl.endsWith('.vtt')) return 'vtt';
            if (cleanUrl.endsWith('.srt')) return 'srt';
            if (cleanUrl.endsWith('.ass')) return 'ass';
            if (cleanUrl.endsWith('.ssa')) return 'ssa';
            if (cleanUrl.endsWith('.ttml') || cleanUrl.endsWith('.xml'))
                return 'ttml';

            return 'vtt';
        };

        if (!apiResponse.success) {
            return this.emptyResult('AnyEmbed returned unsuccessful response');
        }

        for (const providerSource of apiResponse.sources ?? []) {
            for (const stream of providerSource.streams ?? []) {
                const type = inferSourceType(stream.url);

                sources.push({
                    url: this.createProxyUrl(stream.url, stream.headers),
                    type,
                    quality: stream.quality || 'unknown',
                    audioTracks: [
                        {
                            label: 'English',
                            language: 'en'
                        }
                    ],
                    provider: {
                        id: this.id,
                        name: this.name
                    }
                });

                for (const sub of stream.subtitles ?? []) {
                    const key = `${sub.url}::${sub.label}`;
                    if (!subtitlesMap.has(key)) {
                        const format = inferSubtitleFormat(sub.url);

                        subtitlesMap.set(key, {
                            url: this.createProxyUrl(sub.url),
                            label: sub.label || sub.language || 'Unknown',
                            format
                        });
                    }
                }
            }
        }

        return {
            sources,
            subtitles: [...subtitlesMap.values()],
            diagnostics
        };
    }

    /**
     * Return empty result with diagnostic
     */
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
}
