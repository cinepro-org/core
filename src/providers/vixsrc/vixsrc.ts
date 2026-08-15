import { BaseProvider } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source,
    Subtitle
} from '@omss/framework';
import type { VixSrcApiResponse } from './vixsrc.types.ts';

export class VixSrcProvider extends BaseProvider {
    readonly id = 'vixsrc';
    readonly name = 'VixSrc';
    readonly enabled = true;
    readonly BASE_URL = 'https://vixsrc.to';
    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150 Safari/537.36',
        Accept: 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9',
        Referer: this.BASE_URL,
        Origin: this.BASE_URL
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

    /**
     * Main scraping logic
     */
    private async getSources(
        media: ProviderMediaObject
    ): Promise<ProviderResult> {
        try {
            const pageUrl = this.buildPageUrl(media);

            const sublink = await this.fetchApi(pageUrl);
            if (!sublink) {
                return this.emptyResult('Failed to fetch api', media);
            }

            const html = await this.fetchPage(sublink.src);
            if (!html) {
                return this.emptyResult(
                    'Failed to fetch second embed page',
                    media
                );
            }

            const tokenData = this.extractTokenData(html, media);
            if (!tokenData) {
                return this.emptyResult('Invalid or expired token', media);
            }

            const masterUrl = this.buildMasterUrl(tokenData);

            const playlistContent = await this.fetchPlaylist(
                masterUrl,
                pageUrl,
                media
            );
            if (!playlistContent) {
                return this.emptyResult('Failed to fetch playlist', media);
            }

            return this.parsePlaylist(
                playlistContent,
                masterUrl,
                pageUrl,
                media
            );
        } catch (error) {
            return this.emptyResult(
                error instanceof Error
                    ? error.message
                    : 'Unknown provider error',
                media
            );
        }
    }

    /**
     * Build page URL based on media type
     */
    private buildPageUrl(media: ProviderMediaObject): string {
        if (media.type === 'movie') {
            return `${this.BASE_URL}/api/movie/${media.tmdbId}`;
        } else {
            return `${this.BASE_URL}/api/tv/${media.tmdbId}/${media.s}/${media.e}`;
        }
    }

    /**
     * Fetch page HTML
     */
    private async fetchApi(url: string): Promise<VixSrcApiResponse | null> {
        try {
            const response = await fetch(url, {
                headers: this.HEADERS
            });

            if (response.status !== 200) {
                return null;
            }

            return (await response.json()) as VixSrcApiResponse;
        } catch {
            return null;
        }
    }

    private async fetchPage(suburl: string): Promise<string | null> {
        try {
            const response = await fetch(this.BASE_URL + suburl, {
                headers: this.HEADERS
            });

            if (response.status !== 200) {
                return null;
            }

            return await response.text();
        } catch {
            return null;
        }
    }

    /**
     * Extract token, expires, and playlist URL from HTML
     */
    private extractTokenData(
        html: string,
        media: ProviderMediaObject
    ): { token: string; expires: string; playlist: string } | null {
        const token = html.match(/token["']\s*:\s*["']([^"']+)/)?.[1];
        const expires = html.match(/expires["']\s*:\s*["']([^"']+)/)?.[1];
        const playlist = html.match(/url\s*:\s*["']([^"']+)/)?.[1];

        if (!token || !expires || !playlist) {
            return null;
        }

        if (this.isTokenExpired(expires)) {
            return null;
        }

        return { token, expires, playlist };
    }

    /**
     * Check if token is expired
     */
    private isTokenExpired(expires: string): boolean {
        return parseInt(expires, 10) * 1000 - 60_000 < Date.now();
    }

    /**
     * Build master playlist URL with token
     */
    private buildMasterUrl(tokenData: {
        token: string;
        expires: string;
        playlist: string;
    }): string {
        const { token, expires, playlist } = tokenData;
        const separator = playlist.includes('?') ? '&' : '?';
        return `${playlist}${separator}token=${token}&expires=${expires}&h=1`;
    }

    /**
     * Fetch playlist content
     */
    private async fetchPlaylist(
        url: string,
        referer: string,
        media: ProviderMediaObject
    ): Promise<string | null> {
        try {
            const response = await fetch(url, {
                headers: {
                    ...this.HEADERS,
                    Referer: referer
                }
            });

            if (response.status !== 200) {
                return null;
            }

            return await response.text();
        } catch {
            return null;
        }
    }

    /**
     * Parse HLS playlist content
     */
    private parsePlaylist(
        content: string,
        masterUrl: string,
        pageUrl: string,
        media: ProviderMediaObject
    ): ProviderResult {
        const audioTracks = this.parseAudioTracks(content);
        const subtitles = this.parseSubtitles(content, pageUrl);
        const variants = this.parseVariants(content);

        if (variants.length === 0) {
            return this.emptyResult('No streams found in playlist', media);
        }

        const bestVariant = variants.reduce((best, current) =>
            current.resolution > best.resolution ? current : best
        );

        const sources: Source[] = [
            {
                url: this.createProxyUrl(masterUrl, {
                    ...this.HEADERS,
                    Referer: pageUrl
                }),
                type: 'hls',
                quality: `${bestVariant.resolution}p`,
                audioTracks:
                    audioTracks.length > 0
                        ? audioTracks
                        : [
                              {
                                  language: 'en',
                                  label: 'English'
                              }
                          ],
                provider: {
                    id: this.id,
                    name: this.name
                }
            }
        ];

        return {
            sources,
            subtitles,
            diagnostics:
                sources.length === 0
                    ? [
                          {
                              code: 'PARTIAL_SCRAPE',
                              message: 'No playable streams found',
                              field: 'sources',
                              severity: 'warning'
                          }
                      ]
                    : []
        };
    }

    /**
     * Parse audio tracks from HLS manifest
     */
    private parseAudioTracks(
        content: string
    ): Array<{ language: string; label: string }> {
        const tracks: Array<{ language: string; label: string }> = [];
        const lines = content.split('\n');

        for (const line of lines) {
            if (!line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) continue;

            const language = line.match(/LANGUAGE="([^"]+)"/)?.[1] ?? 'unknown';
            const label = line.match(/NAME="([^"]+)"/)?.[1] ?? 'Audio';

            tracks.push({
                language,
                label
            });
        }

        return tracks;
    }

    /**
     * Parse subtitles from HLS manifest
     */
    private parseSubtitles(content: string, pageUrl: string): Subtitle[] {
        const subtitles: Subtitle[] = [];

        /* Doesn't work..
        // TODO: Fix subtitles for vixsrc
        const lines = content.split('\n');

        for (const line of lines) {
            if (!line.startsWith('#EXT-X-MEDIA:TYPE=SUBTITLES')) continue;

            const url = line.match(/URI="([^"]+)"/)?.[1];
            if (!url) continue;

            const language = line.match(/NAME="([^"]+)"/)?.[1] ?? 'unknown';

            subtitles.push({
                url: this.createProxyUrl(url, {
                    ...this.HEADERS,
                    Referer: pageUrl
                }),
                label: language,
                format: 'vtt'
            });
        }
        */

        return subtitles;
    }

    /**
     * Parse quality variants from HLS manifest
     */
    private parseVariants(
        content: string
    ): Array<{ resolution: number; url: string }> {
        const variants: Array<{ resolution: number; url: string }> = [];
        const regex =
            /#EXT-X-STREAM-INF:[^\n]*RESOLUTION=\d+x(\d+)[^\n]*\n([^\n]+)/g;
        let match;

        while ((match = regex.exec(content)) !== null) {
            variants.push({
                resolution: parseInt(match[1], 10),
                url: match[2]
            });
        }

        return variants;
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
