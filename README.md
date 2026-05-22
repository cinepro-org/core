<a id="readme-top"></a>

<div align="center">

[![Contributors](https://img.shields.io/github/contributors/cinepro-org/core?style=for-the-badge&color=green)](#top-contributors)
[![Forks](https://img.shields.io/github/forks/cinepro-org/core?style=for-the-badge&color=blue)](https://github.com/cinepro-org/core/forks)
[![Stars](https://img.shields.io/github/stars/cinepro-org/core?style=for-the-badge&color=gold)](https://github.com/cinepro-org/core/stargazers)
[![GitHub License](https://img.shields.io/badge/license-PolyForm-orange?style=for-the-badge)
](LICENSE)

# CinePro Core 🎬

### _Support CinePro’s development by starring this repository!_ ⭐

<img src="https://repository-images.githubusercontent.com/1138947882/af901757-a06b-442d-8976-c485fcafc230"></img>

#### OMSS-compliant streaming backend powering the CinePro ecosystem.
Built with [@omss/framework](https://www.npmjs.com/package/@omss/framework) for extensible, type-safe media scraping.

**[📖 Documentation](https://docs.cinepro.cc)** · **[💬 Discussions](https://github.com/orgs/cinepro-org/discussions)** · **[🐛 Issues](https://github.com/cinepro-org/core/issues)**

</div>

---

CinePro Core is the central scraping and streaming engine of the CinePro ecosystem. It exposes an [OMSS-compliant](https://github.com/omss-spec/omss-spec) HTTP API for resolving movie and TV show stream sources from multiple providers, with Redis caching and full Docker support.

It now also includes MCP support for AI agents — making it the first streaming server worldwide to offer this feature.

**Get access to 50+ unique sources for a single movie or TV show!**

> [!CAUTION]
> CinePro Core is designed for **personal and home use only.**  
> While we do not prevent public hosting, it is insecure by default.*
>
> Users are responsible for ensuring compliance with applicable laws and the terms of service of streaming providers.

<details><summary>*:</summary>

CinePro Core is a scraper. This means it automatically navigates through third-party streaming websites to retrieve direct streaming links while bypassing ads and scam redirects.

Because this process consumes computing resources, publicly exposed instances may be vulnerable to abuse or (D)DOS attacks, which can significantly increase hosting costs.

We strongly recommend running CinePro Core locally. More end-user documentation and setup guides will be released soon.

</details>

## Quick Start

**Prerequisites:** Node.js 20+ and a [TMDB API key](https://www.themoviedb.org/settings/api)

```bash
git clone https://github.com/cinepro-org/core.git && cd core
npm install
cp .env.example .env   # add your TMDB_API_KEY and configure additional options if needed
npm run dev            # http://localhost:3000
````

For Docker, production deployment, and advanced configuration options → **[Quickstart](https://docs.cinepro.cc/quickstart)**

## Fork Sync + Vercel Auto Deploy

If you run this on a fork and want automatic deploys from synced upstream commits:

1. Connect your **fork repository** to Vercel (not the upstream repo) and set Production Branch to `main`.
2. In Vercel Project Settings, keep **Auto Deploy** enabled and keep **Ignored Build Step** empty.
3. Add required environment variables in Vercel (at minimum `TMDB_API_KEY`; add any others from `.env.example` as needed).
4. Use the workflow at `/home/runner/work/cinepro/cinepro/.github/workflows/sync-fork.yml` to sync upstream `main` into your fork `main` (manual + every 6 hours).
5. (Optional) Set repository variable `UPSTREAM_REPOSITORY` (example: `cinepro-org/core`) if your upstream is different.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Features

* 🎯 **OMSS-Compliant** – follows the Open Media Streaming Standard
* 🔌 **Modular Providers** – drop-in provider system with auto-discovery
* 🛡️ **Type-Safe** – built with strict TypeScript
* ⚡ **Production-Ready** – Redis caching, Docker support, and robust error handling
* 🎬 **Multi-Source Streaming** – resolves movies and TV shows from multiple providers
* 📺 **Stremio Compatibility** – enable a Stremio addon using the `STREMIO_ADDON` environment variable at `/stremio/manifest.json`
* 📦 **CineHome Integration** *(planned for late 2026)* – compatible with CineHome download automation

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Documentation

Full documentation, API references, configuration guides, and provider development resources are available at **[CinePro Docs](https://docs.cinepro.cc)**.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Pull requests are welcome — especially for new providers, bug fixes, and documentation improvements.

See the [Documentation](https://docs.cinepro.cc/core/general-information/development) and the [Contributing Guidelines](https://github.com/cinepro-org/core?tab=contributing-ov-file#contributing-to-cinepro-core) for more information.

### Top Contributors

<a href="https://github.com/cinepro-org/core/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=cinepro-org/core" alt="contrib.rocks image" />
</a>

*Join the project by contributing!*

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Graphs

![Repobeats analytics image](https://repobeats.axiom.co/api/embed/94fe2818e3f3254c91180779917073d3dbb1ace1.svg "Repobeats analytics image")

<a href="https://www.star-history.com/#cinepro-org/core&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=cinepro-org/core&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=cinepro-org/core&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=cinepro-org/core&type=date&legend=top-left" />
 </picture>
</a>

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## License

PolyForm Noncommercial License 1.0.0 © CinePro Organization — see [LICENSE](LICENSE) for details.

This software does not host, store, or distribute copyrighted content.

Any DMCA complaints should be directed to the hosting provider, not to us.

[Read more here](https://docs.cinepro.cc/core/general-information/license)

<p align="right">(<a href="#readme-top">back to top</a>)</p>
