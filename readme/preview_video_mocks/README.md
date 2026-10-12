# README preview media

This folder contains the fictional climbing and bouldering catalog and artwork used in Alphane's README previews. The featured series is **Chalk up!**. All film and series descriptions, release years, episodes, and productions are invented for these mockups.

## Contents

- `catalog.md` and `catalog.json`: the approved 12 films and 6 series, plus episode metadata, resume positions, and screen arrangements.
- `covers/`: 18 original AI-generated landscape covers, including distinct 1990s film treatments.
- `frames/`: clean frames for **Last Light** (S1:E3) and **New Lines** (S1:E4).
- `backdrops/`: separate season artwork for **Chalk up!**'s Home and play/detail backgrounds.
- `prompts.json`: the exact generation prompts and reference-image relationships. Images were generated with the built-in `image_gen` tool.
- `assets.json`: saved-asset provenance, dimensions, and SHA-256 checksums.
- `render_previews.swift`: the documentation-only SwiftUI compositor.

The four final 1920 × 1080 PNGs live one folder above, directly in `readme/`: `home.png`, `dynamic-sections.png`, `video-finished.png`, and `video-ui.png`.

**Chalk up!** focuses on bouldering. It has a daylight ensemble cover for the series discovery row and a separate clean woodland backdrop for the season. The backdrop is used behind Home's selected Continue item and on the play/detail page. Both depict bouldering and exploration without sport-climbing imagery, and are distinct from the episode frames.

The **Last Light** sunset frame is used for the Continue episode thumbnail and the full playback frame. **New Lines** provides a different image for the Next card. Other series in Continue use fictional episode titles and their series artwork.

## Rendering

From the repository root on macOS with Xcode installed:

```sh
xcrun swift readme/preview_video_mocks/render_previews.swift
```

This rebuilds the four final previews from the checked-in artwork and refreshes `assets.json`. It does not regenerate media, connect to a Jellyfin server, or run Alphane. To replace an artwork asset, use its prompt in `prompts.json`, save the selected result at its `destination`, and rerun the compositor.

## UI fidelity

These are reconstructed UI mockups, composed with native SwiftUI text and SF Symbols. They are not captures of a running Alphane app. The compositor follows the current tvOS source for the theme, Home navigation labels, landscape carousel sizing, focus outlines, cinematic gradients, episode detail layout, Next card, and cinema controls. It is a documentation tool, not an app target; it should be reviewed when those views change.

The key layout sources are:

- `Alphane tvOS/Objects/AlphaneTheme.swift`
- `Alphane tvOS/Objects/HomeDiscoveryRow.swift`
- `Alphane tvOS/Objects/CinematicSelectionContentGroup.swift`
- `Alphane tvOS/Components/CinematicItemSelector.swift`
- `Alphane tvOS/Views/ItemView/TVDetailHeaderContentGroup.swift`
- `Alphane tvOS/Views/VideoPlayer/PlaybackControls/`
- `Shared/Coordinators/Tabs/MainTabView.swift`
- `Shared/Components/PosterHStack.swift`
- `Shared/Components/ButtonStyles/FocusBorderButtonStyle.swift`
- `Shared/Extensions/EdgeInsets.swift`

Each discovery row has six eligible entries, matching the app's minimum item count. At this scroll position the Home navigation header is hidden. The completed-episode preview reproduces the existing detail page and focused **Next** card. The player shows the paused **Last Light** episode at **25:14 / 42:00**, consistent with the Home resume position.

## Artwork provenance

The media images were created from the saved text prompts. The generated **Last Light** frame was used as the reference for the next episode's frame. **Chalk up!**'s season cover and clean woodland backdrop use daylight bouldering imagery; a sport-climbing panel in the cover was replaced at the user's request. **Brushwork** was revised from its original generated cover to remove an incorrect climbing pose; its final composition shows only a hand, brush, and rock. The rejected variants are not included. No real movie covers, production stills, or app screenshots were supplied as references. The prompts requested fictional people, unbranded equipment, and original artwork without studio logos or billing blocks. The main README identifies the previews as mockups with fictional media and AI-generated artwork.
