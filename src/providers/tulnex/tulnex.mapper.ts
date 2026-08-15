import type { ExtractedStream } from './tulnex.types.ts';

export function extractUrl(data: any): ExtractedStream | null {
    if (!data) return null;

    const wrap = (
        url: unknown,
        headers: Record<string, string> | null = null
    ): ExtractedStream | null => {
        if (!url || typeof url !== 'string' || !url.includes('http'))
            return null;
        return { url, headers };
    };

    if (typeof data === 'string' && data.includes('http')) return wrap(data);

    const d = data as Record<string, unknown>;
    const headers = (d.headers as Record<string, string>) ?? null;

    if (typeof d.url === 'string' && d.url.includes('http'))
        return wrap(d.url, headers);
    if (typeof d.stream === 'string' && d.stream.includes('http'))
        return wrap(d.stream, headers);
    if (typeof d.playlist === 'string' && d.playlist.includes('http'))
        return wrap(d.playlist, headers);
    if (typeof d.streamUrl === 'string' && d.streamUrl.includes('http'))
        return wrap(d.streamUrl, headers);
    if (typeof d.stream_url === 'string' && d.stream_url.includes('http'))
        return wrap(d.stream_url, headers);
    if (typeof d.streaming_url === 'string' && d.streaming_url.includes('http'))
        return wrap(d.streaming_url, headers);
    if (typeof d.video_url === 'string' && d.video_url.includes('http'))
        return wrap(d.video_url, headers);
    if (typeof d.m3u8 === 'string' && d.m3u8.includes('http'))
        return wrap(d.m3u8, headers);

    const srcsPrimary = (d.sources as Record<string, unknown>)?.primary as
        | Record<string, unknown>
        | undefined;
    if (srcsPrimary?.url)
        return wrap(
            srcsPrimary.url,
            (srcsPrimary.headers as Record<string, string>) ?? headers
        );

    if (Array.isArray(d.sources) && d.sources.length > 0) {
        const sorted = (d.sources as Record<string, unknown>[])
            .filter(
                (s) =>
                    typeof s.url === 'string' &&
                    (s.url as string).includes('http')
            )
            .sort((a, b) => {
                const qa = parseInt(
                    ((a.quality as string) ?? '').replace('p', '') || '0'
                );
                const qb = parseInt(
                    ((b.quality as string) ?? '').replace('p', '') || '0'
                );
                return qb - qa;
            });
        if (sorted.length > 0)
            return wrap(
                sorted[0].url,
                (sorted[0].headers as Record<string, string>) ?? headers
            );
    }

    if (Array.isArray(d.languages)) {
        const orig = (d.languages as Record<string, unknown>[]).find(
            (l) =>
                l.original === true &&
                Array.isArray(l.sources) &&
                (l.sources as unknown[]).length > 0
        );
        if (orig) {
            const sorted = [
                ...(orig.sources as Record<string, unknown>[])
            ].sort(
                (a, b) =>
                    parseInt(
                        ((b.quality as string) ?? '').replace('p', '') || '0'
                    ) -
                    parseInt(
                        ((a.quality as string) ?? '').replace('p', '') || '0'
                    )
            );
            return wrap(
                sorted[0].url ?? sorted[0].file,
                (sorted[0].headers as Record<string, string>) ??
                    (orig.headers as Record<string, string>) ??
                    headers
            );
        }
    }

    if (Array.isArray(d.links) && d.links.length > 0) {
        const link = (d.links as Record<string, unknown>[]).find(
            (l) =>
                typeof l.url === 'string' && (l.url as string).includes('http')
        );
        if (link) return wrap(link.url, headers);
    }

    const nestedData = d.data as Record<string, unknown> | undefined;
    if (
        nestedData?.data &&
        (nestedData.data as Record<string, unknown>)?.stream
    )
        return wrap(
            (
                (nestedData.data as Record<string, unknown>).stream as Record<
                    string,
                    unknown
                >
            )?.playlist,
            headers
        );
    if (nestedData?.stream)
        return wrap(
            (nestedData.stream as Record<string, unknown>)?.playlist,
            headers
        );
    if (typeof nestedData?.url === 'string' && nestedData.url.includes('http'))
        return wrap(
            nestedData.url,
            (nestedData.headers as Record<string, string>) ?? headers
        );

    if (Array.isArray(nestedData?.sources)) {
        const src = (nestedData!.sources as Record<string, unknown>[]).find(
            (s) =>
                typeof s.url === 'string' && (s.url as string).includes('http')
        );
        if (src)
            return wrap(
                src.url,
                (src.headers as Record<string, string>) ?? headers
            );
    }

    if (Array.isArray(d.streams)) {
        const src = (d.streams as Record<string, unknown>[]).find(
            (s) =>
                (typeof s.url === 'string' &&
                    (s.url as string).includes('http')) ||
                (typeof s.link === 'string' &&
                    (s.link as string).includes('http'))
        );
        if (src)
            return wrap(
                src.url ?? src.link,
                (src.headers as Record<string, string>) ?? headers
            );
    }

    return null;
}
