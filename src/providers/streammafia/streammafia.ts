import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Subtitle,
    AudioTrack,
    Diagnostic,
    Source,
    SourceType
} from '@omss/framework';
import { BaseProvider } from '@omss/framework';
import type { ApiResponse, EncryptedPayload, Switch } from './streammafia.types.ts';
import { decryptStreamMafia } from './decrypt.ts';
import { generateRandomUserAgent } from '../../utils/ua.ts';

export class StreamMafiaProvider extends BaseProvider {
    readonly id = 'streammafia';
    readonly name = 'MafiaEmbed';
    readonly enabled = true;
    readonly BASE_URL = 'https://player.nhdapi.com';
    readonly HEADERS = {
        'User-Agent': '',
        Accept: 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9',
        Referer: this.BASE_URL + '/',
        Origin: this.BASE_URL,
        Cookie: '',
        'x-api-token': '',
        'x-content-id': ''
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

    async healthCheck(): Promise<boolean> {
        try {
            const res = await fetch(this.BASE_URL, {
                method: 'HEAD',
                headers: this.HEADERS
            });
            return res.status === 200;
        } catch {
            return false;
        }
    }

    private async getSources(
        media: ProviderMediaObject
    ): Promise<ProviderResult> {
        try {
            this.HEADERS['User-Agent'] = generateRandomUserAgent();
            this.HEADERS['x-content-id'] = media.tmdbId.toString();

            const cookie: string = await this.getSessionCookie();
            if (!cookie) {
                return this.emptyResult('Failed to retrieve session cookie');
            }

            this.HEADERS.Cookie =
                cookie.split(';')[0] ||
                'vid_session=' +
                    Buffer.from(
                        JSON.stringify({
                            id: media.tmdbId,
                            iat: Math.floor(Date.now() / 1000)
                        })
                    ).toString('base64');

            await new Promise((resolve) => setTimeout(resolve, 100));

            const token: string = await this.getToken();
            if (!token) {
                return this.emptyResult('Failed to retrieve access token');
            }

            this.HEADERS['x-api-token'] = token;

            const url = this.buildPageUrl(media);
            const encrypted = await this.fetchPage(url);

            if (!encrypted) {
                return this.emptyResult('Invalid API response');
            }

            const api = decryptStreamMafia(encrypted);
            return await this.mapApiResponse(api);
        } catch (err) {
            return this.emptyResult(
                err instanceof Error ? err.message : 'Auto error'
            );
        }
    }

    private async getToken(): Promise<string> {
        try {
            const res = await fetch(`${this.BASE_URL}/api/token`, {
                headers: { ...this.HEADERS },
                referrer: this.BASE_URL + '/'
            });
            if (res.status !== 200) return '';
            const data = (await res.json()) as { token?: string };
            return data.token || '';
        } catch {
            return '';
        }
    }

    private async getSessionCookie(): Promise<string> {
        try {
            const res = await fetch(this.BASE_URL + '/api/session', {
                method: 'POST',
                headers: this.HEADERS,
                body: null
            });
            return res.headers.get('Set-Cookie') || '';
        } catch {
            return '';
        }
    }

    private buildPageUrl(media: ProviderMediaObject): string {
        if (media.type === 'movie') {
            return `${this.BASE_URL}/api/movie/?id=${media.tmdbId}`;
        }

        return `${this.BASE_URL}/api/?tv=${media.tmdbId}&season=${media.s}&episode=${media.e}`;
    }

    private async fetchPage(url: string): Promise<EncryptedPayload | null> {
        try {
            const res = await fetch(url, { headers: this.HEADERS });
            if (res.status !== 200) return null;
            return (await res.json()) as EncryptedPayload;
        } catch {
            return null;
        }
    }

    private async mapApiResponse(api: ApiResponse): Promise<ProviderResult> {
        const sources: Source[] = [];
        const subtitles: Subtitle[] = [];
        const diagnostics: Diagnostic[] = [];

        const fallbackAudio = this.extractAudioTrack(api.selected);

        // main stream
        const mainSources = await this.extractSourcesFromApi(
            api,
            fallbackAudio
        );
        sources.push(...mainSources);

        // switches in parallel
        if ((api.switches?.length ?? 0) > 0) {
            const switchResults = await Promise.all(
                api.switches.map((sw) => this.resolveSwitch(sw))
            );

            for (const result of switchResults) {
                sources.push(...result);
            }
        }

        if (sources.length === 0) {
            diagnostics.push({
                code: 'PROVIDER_ERROR',
                message: `${this.name}: No playable sources found`,
                field: '',
                severity: 'error'
            });
        }

        // dedupe
        const seen = new Set<string>();
        const deduped: Source[] = [];

        for (const s of sources) {
            if (seen.has(s.url)) continue;
            seen.add(s.url);
            deduped.push(s);
        }

        return { sources: deduped, subtitles, diagnostics };
    }

    private async resolveSwitch(sw: Switch): Promise<Source[]> {
        try {
            const url = `${this.BASE_URL}/api/source/${sw.file_code}`;
            const encrypted = await this.fetchPage(url);

            if (!encrypted) return [];

            const api = decryptStreamMafia(encrypted);

            const fallbackAudio: AudioTrack = {
                language: sw.lang_code?.toLowerCase() || 'Auto',
                label: sw.lang || sw.lang_code || 'Auto'
            };

            return await this.extractSourcesFromApi(api, fallbackAudio);
        } catch {
            return [];
        }
    }

    private async extractSourcesFromApi(
        api: ApiResponse,
        fallbackAudio: AudioTrack
    ): Promise<Source[]> {
        const sources: Source[] = [];

        if (api.stream?.hls_streaming) {
            const parsed = await this.parseHLS(api.stream.hls_streaming);

            sources.push({
                url: this.createProxyUrl(api.stream.hls_streaming, {
                    'User-Agent': ''
                }),
                type: 'hls',
                quality: parsed.quality || 'auto',
                audioTracks:
                    parsed.audioTracks.length > 0
                        ? parsed.audioTracks
                        : [fallbackAudio],
                provider: {
                    id: this.id,
                    name: this.name
                }
            });
        }

        for (const download of api.stream?.download ?? []) {
            sources.push({
                url: this.createProxyUrl(api.stream.hls_streaming, {
                    'User-Agent': ''
                }),
                type: this.inferSourceType(download.url),
                quality: this.normalizeQuality(download.quality, 'Auto'),
                audioTracks: [fallbackAudio],
                provider: {
                    id: this.id,
                    name: this.name
                }
            });
        }

        return sources;
    }

    private extractAudioTrack(selected: ApiResponse['selected']): AudioTrack {
        const language =
            selected?.lang_code?.trim().toLowerCase() ||
            selected?.lang?.trim().toLowerCase() ||
            'Auto';

        const label =
            selected?.lang?.trim() ||
            selected?.lang_code?.toUpperCase() ||
            'Auto';

        return { language, label };
    }

    private async parseHLS(url: string): Promise<{
        quality: string;
        audioTracks: AudioTrack[];
    }> {
        try {
            const res = await fetch(url, {
                headers: {
                    ...this.HEADERS,
                    Referer: this.BASE_URL + '/'
                }
            });

            const content: string = await res.text();
            const variants = this.parseVariants(content);
            const audioTracks = this.parseAudioTracks(content);

            if (variants.length === 0) {
                return { quality: 'Auto', audioTracks };
            }

            const best = variants.reduce((a, b) =>
                b.resolution > a.resolution ? b : a
            );

            return {
                quality: best.resolution.toString(),
                audioTracks
            };
        } catch {
            return { quality: 'auto', audioTracks: [] };
        }
    }

    private parseVariants(content: string): Array<{ resolution: number }> {
        const variants: Array<{ resolution: number }> = [];
        const regex = /RESOLUTION=\d+x(\d+)[^\n]*\n([^\n]+)/g;

        let match: RegExpExecArray | null;
        while ((match = regex.exec(content)) !== null) {
            variants.push({
                resolution: parseInt(match[1], 10)
            });
        }

        return variants;
    }

    private parseAudioTracks(content: string): AudioTrack[] {
        const tracks: AudioTrack[] = [];
        const lines = content.split('\n');

        for (const line of lines) {
            if (!line.includes('TYPE=AUDIO')) continue;

            const language =
                line.match(/LANGUAGE="([^"]+)"/)?.[1]?.toLowerCase() ?? 'Auto';
            const label = line.match(/NAME="([^"]+)"/)?.[1] ?? language;

            tracks.push({ language, label });
        }

        return tracks;
    }

    private inferSourceType(url: string): SourceType {
        const clean = url.toLowerCase().split('?')[0];

        if (clean.endsWith('.m3u8')) return 'hls';
        if (clean.endsWith('.mpd')) return 'dash';
        if (clean.endsWith('.mp4')) return 'mp4';
        if (clean.endsWith('.mkv')) return 'mkv';
        if (clean.endsWith('.webm')) return 'webm';

        return 'hls';
    }

    private normalizeQuality(value?: string, fallback = 'Auto'): string {
        if (!value) return fallback;

        const v = value.toLowerCase();

        if (v.includes('2160')) return '2160';
        if (v.includes('1080')) return '1080';
        if (v.includes('720')) return '720';
        if (v.includes('480')) return '480';
        if (v.includes('360')) return '360';
        if (v.includes('240')) return '240';

        return value;
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
