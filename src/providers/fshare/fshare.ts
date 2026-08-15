import { BaseProvider } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    SourceType
} from '@omss/framework';
import type { FshareResponse, FshareSource } from './fshare.types.ts';

export class FsharetvProvider extends BaseProvider {
    readonly id = 'fsharetv';
    readonly name = 'FshareTV';
    readonly enabled = true;

    readonly BASE_URL = 'https://fsharetv.cc';
    private readonly TRAILER = 'Png81APqcxU';

    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        Referer: this.BASE_URL
    };

    private readonly API_HEADERS = {
        ...this.HEADERS,
        Accept: 'application/json, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest'
    };

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies']
    };

    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        try {
            const watchPath = await this.findWatchPath(media.imdbId);
            if (!watchPath)
                return this.emptyResult(
                    `No watch page found for IMDb ID ${media.imdbId}`
                );

            const sourceId = await this.extractSourceId(watchPath);
            if (!sourceId)
                return this.emptyResult(
                    `No source ID found for watch path ${watchPath}`
                );

            const resp = await this.fetchApi(sourceId);
            if (!resp)
                return this.emptyResult(
                    `API request failed for source ID ${sourceId}`
                );

            return this.mapToProviderResult(resp);
        } catch (error) {
            return {
                sources: [],
                subtitles: [],
                diagnostics: [
                    {
                        code: 'PROVIDER_ERROR',
                        message:
                            error instanceof Error
                                ? error.message
                                : 'Unknown error',
                        field: '',
                        severity: 'error'
                    }
                ]
            };
        }
    }

    async getTVSources(_media: ProviderMediaObject): Promise<ProviderResult> {
        return { sources: [], subtitles: [], diagnostics: [] };
    }

    async healthCheck(): Promise<boolean> {
        try {
            const res = await fetch(this.BASE_URL, {
                method: 'HEAD',
                headers: this.HEADERS
            });
            return res.ok;
        } catch {
            return false;
        }
    }

    private async findWatchPath(imdbId: string): Promise<string | null> {
        const res = await fetch(`${this.BASE_URL}/movie/${imdbId}`, {
            headers: this.HEADERS
        });
        if (!res.ok) return null;
        const html = await res.text();
        const match = html.match(/href="(\/w\/[^"]+)"/);
        return match ? match[1] : null;
    }

    private async extractSourceId(watchPath: string): Promise<string | null> {
        const res = await fetch(`${this.BASE_URL}${watchPath}`, {
            headers: this.HEADERS
        });
        if (!res.ok) return null;
        const html = await res.text();

        const patterns = [
            /Movie\.setSource\("([^"]+)"/,
            /setSource\("([^"]+)"/,
            /setSource\('([^']+)'/,
            /"source_id"\s*:\s*"([^"]+)"/,
            /source_id\s*=\s*"([^"]+)"/,
            /file_id\s*=\s*"([^"]+)"/,
            /"file_id"\s*:\s*"([^"]+)"/
        ];

        for (const pattern of patterns) {
            const match = html.match(pattern);
            if (match) return match[1];
        }
        return null;
    }

    private async fetchApi(sourceId: string): Promise<FshareResponse | null> {
        const url = `${this.BASE_URL}/api/file/${sourceId}/source?trailer=${this.TRAILER}&type=watch`;
        const res = await fetch(url, {
            headers: { ...this.API_HEADERS, Referer: `${this.BASE_URL}/` }
        });
        if (!res.ok) return null;
        const json = (await res.json()) as FshareResponse;
        return json.status === 'ok' ? json : null;
    }

    private mapToProviderResult(resp: FshareResponse): ProviderResult {
        const file = resp.data?.file;

        const allSources: FshareSource[] = [
            ...(file?.sources ?? []),
            ...(file?.backups ?? []),
            ...(file?.alternatives?.flat() ?? [])
        ];

        const uniqueSources = Array.from(
            new Map(allSources.map((s) => [s.src, s])).values()
        );

        const sources = uniqueSources
            .filter((s) => Boolean(s?.src))
            .sort((a, b) => Number(b.quality ?? 0) - Number(a.quality ?? 0))
            .map((s) => {
                const rawUrl = s.src.startsWith('http')
                    ? s.src
                    : `${this.BASE_URL}${s.src}`;

                return {
                    url: this.createProxyUrl(rawUrl, this.HEADERS),
                    type: (s.type.replace('video/', '') || 'mp4') as SourceType,
                    quality: this.inferQuality(s.label) ?? 'Auto',
                    audioTracks: [
                        {
                            language: 'org',
                            label: 'Original'
                        }
                    ],
                    provider: {
                        id: this.id,
                        name: this.name
                    }
                };
            });

        if (!sources.length) {
            return this.emptyResult(
                'API returned ok but contained no playable sources'
            );
        }

        return {
            sources,
            subtitles: [],
            diagnostics: []
        };
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
}
