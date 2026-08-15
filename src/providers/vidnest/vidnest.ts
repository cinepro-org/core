import { BaseProvider } from '@omss/framework';
import type {
    Diagnostic,
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source,
    SourceType,
    Subtitle,
    SubtitleFormat
} from '@omss/framework';

import decrypt from './decrypt.ts';
import type {
    ServerMap,
    SupportedServer,
    klikxxiResponse,
    allmoviesResponse,
    onehdResponse,
    hollymoviehdResponse,
    vidlinkResponse,
    purstreamResponse,
    deltaResponse,
    movieboxSource
} from './vidnest.types.ts';

export class VidNestProvider extends BaseProvider {
    readonly id = 'vidnest';
    readonly name = 'VidNest';
    readonly enabled = true;

    readonly BASE_URL = 'https://vidnest.fun';
    readonly API_BASE_URL = 'https://new.vidnest.fun';

    readonly HEADERS: Record<string, string> = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150 Safari/537.36',
        Accept: 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9',
        Referer: `${this.BASE_URL}/`,
        Origin: this.BASE_URL
    };

    /**
     * ALL servers (some unsupported)
     */
    private readonly SERVERS: { path: string; query: string }[] = [
        { path: 'moviebox', query: '' },
        { path: 'allmovies', query: '' },
        { path: 'catflix', query: '' },
        { path: 'purstream', query: '' },
        { path: 'hollymoviehd', query: '' },
        { path: 'lamda', query: '' },
        { path: 'flixhq', query: '' },
        { path: 'vidlink', query: '' },
        { path: 'onehd', query: '?server=upcloud' },
        { path: 'klikxxi', query: '' }
    ];

    private readonly handlers: {
        [K in SupportedServer]: {
            parse: (data: string) => ServerMap[K];
            mapSources: (root: ServerMap[K]) => Source[];
            mapSubtitles: (root: ServerMap[K]) => Subtitle[];
        };
    } = {
        klikxxi: {
            parse: (d) => decrypt<klikxxiResponse>(d),
            mapSources: (root) =>
                root.sources.map((s) => ({
                    url: this.createProxyUrl(s.url),
                    type: this.inferSourceType(s.type, s.url),
                    quality: s.quality,
                    audioTracks: [{ language: 'English', label: 'eng' }],
                    provider: { id: this.id, name: this.name }
                })),
            mapSubtitles: () => []
        },

        allmovies: {
            parse: (d) => decrypt<allmoviesResponse>(d),
            mapSources: (root) =>
                root.streams.map((s) => ({
                    url: this.createProxyUrl(s.url),
                    type: this.inferSourceType(s.type, s.url),
                    quality: 'Auto',
                    audioTracks: [{ language: s.language, label: s.language }],
                    provider: { id: this.id, name: this.name }
                })),
            mapSubtitles: () => []
        },

        onehd: {
            parse: (d) => decrypt<onehdResponse>(d),
            mapSources: (root) => [
                {
                    url: this.createProxyUrl(root.url, root.headers),
                    type: this.inferSourceType('', root.url),
                    quality: 'Auto',
                    audioTracks: [{ language: 'English', label: 'eng' }],
                    provider: { id: this.id, name: this.name }
                }
            ],
            mapSubtitles: (root) =>
                root.subtitles.map((s) => ({
                    url: this.createProxyUrl(s.url, root.headers),
                    label: s.lang,
                    format: this.inferSubtitleFormat(s.url)
                }))
        },

        hollymoviehd: {
            parse: (d) => decrypt<hollymoviehdResponse>(d),
            mapSources: (root) =>
                root.sources.map((s) => ({
                    url: this.createProxyUrl(s.file),
                    type: this.inferSourceType(s.type, s.file),
                    quality: s.label,
                    audioTracks: [{ language: 'English', label: 'eng' }],
                    provider: { id: this.id, name: this.name }
                })),
            mapSubtitles: () => []
        },

        vidlink: {
            parse: (d) => decrypt<vidlinkResponse>(d),
            mapSources: (root) => [
                {
                    url: this.createProxyUrl(
                        root.data.stream.playlist,
                        root.headers
                    ),
                    type: this.inferSourceType(
                        root.data.stream.type,
                        root.data.stream.playlist
                    ),
                    quality: 'Auto',
                    audioTracks: [{ language: 'English', label: 'eng' }],
                    provider: { id: this.id, name: this.name }
                }
            ],
            mapSubtitles: (root) =>
                root.data.stream.captions.map((c) => ({
                    url: this.createProxyUrl(c.url, root.headers),
                    label: c.language,
                    format: this.inferSubtitleFormat(c.url)
                }))
        },

        delta: {
            parse: (d) => decrypt<deltaResponse>(d),
            mapSources: (root) =>
                root.streams.map((s) => ({
                    url: this.createProxyUrl(s.url),
                    type: this.inferSourceType(s.type, s.url),
                    quality: 'Auto',
                    audioTracks: [
                        { language: s.language.slice(0, 3), label: s.language }
                    ],
                    provider: { id: this.id, name: this.name }
                })),
            mapSubtitles: () => []
        },

        purstream: {
            parse: (d) => decrypt<purstreamResponse>(d),
            mapSources: (root) =>
                root.sources.map((s) => ({
                    url: this.createProxyUrl(s.url),
                    type: this.inferSourceType(s.format, s.url),
                    quality: this.inferQuality(s.name),
                    audioTracks: [{ language: 'French', label: 'fr' }],
                    provider: { id: this.id, name: this.name }
                })),
            mapSubtitles: () => []
        },

        moviebox: {
            parse: (d) => decrypt<movieboxSource>(d),
            mapSources: (root) =>
                root.url.map((u) => ({
                    url: this.createProxyUrl(u.link, this.HEADERS),
                    type: this.inferSourceType(u.type, u.link),
                    quality: 'Auto',
                    audioTracks: [
                        { language: u.lang.slice(0, 3), label: u.lang }
                    ],
                    provider: { id: this.id, name: this.name }
                })),
            mapSubtitles: () => []
        }
    };

    readonly capabilities: ProviderCapabilities = {
        supportedContentTypes: ['movies', 'tv']
    };

    async getMovieSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media);
    }

    async getTVSources(media: ProviderMediaObject): Promise<ProviderResult> {
        return this.getSources(media);
    }

    private async getSources(
        media: ProviderMediaObject
    ): Promise<ProviderResult> {
        const sources: Source[] = [];
        const subtitles: Subtitle[] = [];
        const diagnostics: Diagnostic[] = [];

        const promises = this.SERVERS.map((server) => {
            const url =
                media.type === 'movie'
                    ? this.buildMovieUrl(media, server.path) + server.query
                    : this.buildTvUrl(media, server.path) + server.query;

            return this.fetchVidnest(url);
        });

        const results = await Promise.allSettled(promises);

        if (
            results.filter((r) => r.status === 'rejected').length ===
            results.length
        ) {
            diagnostics.push({
                code: 'PARTIAL_SCRAPE',
                field: '',
                message: `${this.name}: ${results.length - results.filter((r) => r.status === 'rejected').length}/${results.length} did not have the requested media`,
                severity: 'error'
            });
        }

        results.forEach((result, i) => {
            if (result.status !== 'fulfilled') return;

            const server = this.SERVERS[i];
            const handler = this.handlers[server.path as SupportedServer];

            if (!handler) {
                diagnostics.push({
                    code: 'PARTIAL_SCRAPE',
                    field: '',
                    message: `${this.name}: ${server.path} returned sources, but we don't have a handler for it yet (check for updates: https://github.com/cinepro-org/core).`,
                    severity: 'warning'
                });
                return;
            }
            const key = server.path as SupportedServer;

            if (!(key in this.handlers)) return;

            const { sources: s, subtitles: sub } = this.handleServer(
                key,
                result.value.data
            );

            sources.push(...s);
            subtitles.push(...sub);
        });

        return {
            sources,
            subtitles,
            diagnostics
        };
    }

    private handleServer<K extends SupportedServer>(
        key: K,
        data: string
    ): { sources: Source[]; subtitles: Subtitle[] } {
        const handler = this.handlers[key];
        const root = handler.parse(data);

        return {
            sources: handler.mapSources(root),
            subtitles: handler.mapSubtitles(root)
        };
    }

    private buildMovieUrl(media: ProviderMediaObject, server: string) {
        return `${this.API_BASE_URL}/${server}/movie/${media.tmdbId}`;
    }

    private buildTvUrl(media: ProviderMediaObject, server: string) {
        return `${this.API_BASE_URL}/${server}/tv/${media.tmdbId}/${media.s}/${media.e}`;
    }

    private async fetchVidnest(url: string) {
        const res = await fetch(url, { headers: this.HEADERS });

        if (!res.ok) {
            throw new Error(`VidNest: ${res.status}`);
        }

        return res.json() as Promise<{ encrypted: boolean; data: string }>;
    }

    private inferSourceType(type: string, url: string): SourceType {
        const t = (type ?? '').toLowerCase();
        if (t === 'hls' || url.includes('.m3u8')) return 'hls';
        if (t === 'dash' || url.includes('.mpd')) return 'dash';
        if (t === 'mp4' || url.includes('.mp4')) return 'mp4';
        if (t === 'mkv' || url.includes('.mkv')) return 'mkv';
        if (t === 'webm' || url.includes('.webm')) return 'webm';
        if (t === 'embed') return 'embed';
        return 'hls';
    }

    private inferSubtitleFormat(url: string): SubtitleFormat {
        const u = url.toLowerCase();
        if (u.includes('.vtt')) return 'vtt';
        if (u.includes('.srt')) return 'srt';
        if (u.includes('.ass')) return 'ass';
        if (u.includes('.ssa')) return 'ssa';
        if (u.includes('.ttml')) return 'ttml';
        return 'vtt';
    }
}
