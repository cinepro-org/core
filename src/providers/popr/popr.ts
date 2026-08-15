import { BaseProvider } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source,
    SourceType,
    Subtitle
} from '@omss/framework';
import type { VidnestResponse } from './popr.types.ts';

export class PoprProvider extends BaseProvider {
    readonly id = 'popr';
    readonly name = 'Popr';
    readonly enabled = true;
    readonly BASE_URL = 'https://popr.ink';
    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150 Safari/537.36',
        Referer: `${this.BASE_URL}/`
    };

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies', 'tv']
    };

    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        try {
            let movieSource = await this.fetchSource(media, 'movie');

            return {
                sources: movieSource.sources,
                subtitles: movieSource.subtitles,
                diagnostics: []
            };
        } catch (error) {
            return this.emptyResult(
                error instanceof Error
                    ? error.message
                    : 'error at getting source',
                media
            );
        }
    }

    async getTVSources(media: ProviderMediaObject): Promise<ProviderResult> {
        try {
            let tvSource = await this.fetchSource(media, 'tv');

            return {
                sources: tvSource.sources,
                subtitles: tvSource.subtitles,
                diagnostics: []
            };
        } catch (error) {
            return this.emptyResult(
                error instanceof Error
                    ? error.message
                    : 'error at getting source',
                media
            );
        }
    }

    private async checkStreamType(
        url: string,
        headers: Record<string, string> = {},
        serverName: string
    ): Promise<{ isValid: boolean; type: SourceType }> {
        try {
            const res = await fetch(url, {
                headers: { ...this.HEADERS, ...headers },
                signal: AbortSignal.timeout(5000),
                redirect: 'follow'
            });

            if (!res.ok) {
                return { isValid: false, type: 'mp4' };
            }

            const contentType = res.headers.get('content-type') || '';
            if (
                contentType.includes('video/mp4') ||
                contentType.includes('video/webm')
            ) {
                return { isValid: true, type: 'mp4' };
            }

            const text = await res.text();
            const trimmed = text.trim();

            if (trimmed.startsWith('#EXTM3U')) {
                const segmentLines = trimmed.split('\n').filter((l) => {
                    const t = l.trim();
                    return t && !t.startsWith('#');
                });

                if (segmentLines.length === 0) {
                    return { isValid: false, type: 'hls' };
                }

                return { isValid: true, type: 'hls' };
            }

            if (
                trimmed.toLowerCase().includes('<!doctype html>') ||
                trimmed.toLowerCase().includes('<html')
            ) {
                return { isValid: false, type: 'mp4' };
            }

            return { isValid: true, type: 'mp4' };
        } catch (error) {
            return { isValid: false, type: 'mp4' };
        }
    }

    private async fetchSource(
        media: ProviderMediaObject,
        type: 'tv' | 'movie' = 'movie'
    ): Promise<{ sources: Source[]; subtitles: Subtitle[] }> {
        const servers = [
            'default',
            'catflix',
            'hexa',
            'Gama',
            'Liligoon',
            'Sigma',
            'Prime',
            'Alfa',
            'Lamda',
            'ynx_vidsrc'
        ];

        const ep = media.e || 1;
        const season = media.s || 1;

        const buildUrl = (server: string) => {
            if (type === 'tv') {
                return `${this.BASE_URL}/api/vidnest?id=${media.tmdbId}&type=tv&server=${server}&season=${season}&episode=${ep}`;
            }
            return (
                `${this.BASE_URL}/api/vidnest?id=${media.tmdbId}&type=movie` +
                (server !== 'default' ? `&server=${server}` : '')
            );
        };

        const requests = servers.map((server) =>
            fetch(buildUrl(server), {
                headers: this.HEADERS
            }).then(async (res) => {
                if (res.status !== 200) return null;

                const data = (await res.json()) as VidnestResponse;
                const stream = data?.results?.[0]?.streams?.[0];

                if (!stream?.url) return null;

                const streamHeaders = stream.headers || {};
                const { isValid, type } = await this.checkStreamType(
                    stream.url,
                    streamHeaders,
                    server
                );

                if (!isValid) return null;

                const quality = stream.quality;
                const INVALID_QUALITIES = ['Hindi', 'English', 'MAIN'];
                const QUALITIES = ['Hindi', 'English'];
                const languages = QUALITIES.includes(quality);

                const proxyHeaders = {
                    ...this.HEADERS,
                    ...streamHeaders
                };

                return {
                    source: {
                        url: this.createProxyUrl(stream.url, proxyHeaders),
                        type,
                        quality: INVALID_QUALITIES.includes(quality)
                            ? 'auto'
                            : quality || 'auto',
                        audioTracks: [
                            {
                                language: languages
                                    ? quality.toLowerCase().slice(0, 3)
                                    : 'eng',
                                label: languages ? quality : 'English'
                            }
                        ],
                        provider: { name: this.name, id: this.id }
                    },
                    subtitles: data.results?.[0]?.subtitles || []
                };
            })
        );

        const results = await Promise.allSettled(requests);

        const sources: Source[] = [];
        const subtitlesMap = new Map<string, Subtitle>();

        for (const res of results) {
            if (res.status !== 'fulfilled' || !res.value) continue;

            sources.push(res.value.source);

            for (const sub of res.value.subtitles) {
                if (!sub?.url) continue;

                if (!subtitlesMap.has(sub.url)) {
                    subtitlesMap.set(sub.url, {
                        url: this.createProxyUrl(sub.url),
                        format: 'vtt',
                        label: sub.lang || 'Unknown'
                    });
                }
            }
        }

        return {
            sources,
            subtitles: Array.from(subtitlesMap.values())
        };
    }

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
