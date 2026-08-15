import { BaseProvider } from '@omss/framework';
import type {
    ProviderCapabilities,
    ProviderMediaObject,
    ProviderResult,
    Source,
    SourceType,
    Subtitle
} from '@omss/framework';
import { generateRandomUserAgent } from '../../utils/ua.ts';
import type { VidApiResponse } from './vidapi.types.ts';

export class VidApiProvider extends BaseProvider {
    readonly id = 'vidapi';
    readonly name = 'VidApi';
    readonly enabled = true;
    readonly BASE_URL = 'https://vaplayer.ru';
    readonly IFRAME_URL = 'https://brightpathsignals.com';
    readonly API_URL = 'https://streamdata.vaplayer.ru/api.php';
    readonly HEADERS = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        Referer: `${this.IFRAME_URL}/`,
        Origin: this.IFRAME_URL,
        Accept: '*/*'
    };

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
            this.HEADERS['User-Agent'] = generateRandomUserAgent();
            const type = media.type === 'movie' ? 'movie' : 'tv';

            // Build the API URL with appropriate params
            const url = new URL(this.API_URL);
            url.searchParams.set('tmdb', media.tmdbId);
            url.searchParams.set('type', type);

            if (media.type === 'tv' && media.s != null && media.e != null) {
                url.searchParams.set('season', String(media.s));
                url.searchParams.set('episode', String(media.e));
            }

            const response = await fetch(url.toString(), {
                headers: this.HEADERS
            });

            if (!response.ok) {
                return this.emptyResult(`HTTP error: ${response.status}`);
            }

            const json = (await response.json()) as unknown as VidApiResponse;

            if (json.status_code !== '200' || !json.data) {
                return this.emptyResult(
                    `API returned status: ${json.status_code}`
                );
            }

            const data = json.data;
            const diagnostics: ProviderResult['diagnostics'] = [];

            const sources: Source[] = (data.stream_urls ?? []).map(
                (streamUrl: string): Source => {
                    const sourceType: SourceType =
                        streamUrl.includes('mp4') || streamUrl.includes('mkv')
                            ? 'mp4'
                            : 'hls';

                    return {
                        url: this.createProxyUrl(streamUrl, this.HEADERS),
                        type: sourceType,
                        quality: this.inferQuality(data.file_name),
                        audioTracks: [
                            {
                                label: 'Original',
                                language: 'Original'
                            }
                        ],
                        provider: {
                            id: this.id,
                            name: this.name
                        }
                    };
                }
            );
            const subtitles: Subtitle[] = (json.default_subs ?? []).map(
                (sub: {
                    lang: string;
                    code: string;
                    url: string;
                }): Subtitle => {
                    // Detect subtitle format from file extension
                    const ext = sub.url.split('.').pop()?.toLowerCase();
                    const format =
                        ext === 'vtt'
                            ? 'vtt'
                            : ext === 'ass'
                              ? 'ass'
                              : ext === 'ssa'
                                ? 'ssa'
                                : ext === 'ttml'
                                  ? 'ttml'
                                  : 'srt';

                    return {
                        url: sub.url,
                        label: sub.lang,
                        format
                    };
                }
            );

            return {
                sources,
                subtitles,
                diagnostics
            };
        } catch (e) {
            return this.emptyResult(
                e instanceof Error ? e.message : 'Unknown provider error'
            );
        }
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
