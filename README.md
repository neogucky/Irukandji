<p align="center">
  <img alt="Alphane" src="./Resources/Branding/Alphane-wordmark.png" width="360">
</p>

# Alphane

Alphane is a Jellyfin client for Apple TV, built on Swiftfin and redesigned to look, feel, and behave like a modern streaming app.

The repository also includes an [Alphane theme for Jellyfin Web](./jellyfin-theme/README.md), bringing the same charcoal surfaces, artwork-focused cards, white controls and aqua progress indicators to the browser. It includes a standalone preview, browser checks, installation and rollback tools.

Compared with Swiftfin, Alphane focuses on:

- **Discovery:** cinematic Continue artwork and lazy-loaded recommendation rows with randomized categories and titles.
- **Remote navigation:** direct top navigation, clear focus outlines, consistent controls, and Back navigation that remembers your place.
- **Episode flow:** progress updates after playback and a next-episode action ready when an episode finishes.
- **Playback:** minimal cinema controls with quick access to audio and subtitles.
- **Apple TV Home Screen:** Continue and Next Up artwork through Top Shelf.

## Preview

These UI mockups use fictional climbing and bouldering films and series to avoid any copyright issues.

**Home** — cinematic artwork and progress for the selected Continue item.

![Home with Chalk up! in Continue](./readme/home.png)

**Dynamic sections** — discovery rows based on release decade, genre, and media type allow endless scrolling in the home screen.

![Discovery rows for Movies from the 1990s, Documentaries, and Series from the 2020s](./readme/dynamic-sections.png)

**Episode finished** — the completed episode's detail page, with the next episode ready to play.

![Last Light after playback, with the Next card focused on New Lines](./readme/video-finished.png)

**Video UI** — cinema controls with quick access to episodes, audio, and subtitles.

![Chalk up! paused with the Audio control focused](./readme/video-ui.png)

The [fictional media catalog, artwork, prompts, and preview renderer](./readme/preview_video_mocks/README.md) are included in the repository.

## Build

To build, open `Alphane.xcodeproj` in Xcode and select the `Alphane tvOS` scheme. Local signing overrides belong in the ignored `XcodeConfig/DevelopmentTeam.xcconfig` file.

Report issues and follow development in [this repository](https://github.com/neogucky/alphane).

Alphane is a fork of [Swiftfin](https://github.com/jellyfin/Swiftfin), built by Jellyfin and its contributors, and retains its [Mozilla Public License 2.0](LICENSE.md) and source attribution.
