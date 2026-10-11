# Alphane Top Shelf

Place Alphane in the first row of the Apple TV Home Screen, open it once, and sign in to Jellyfin. Selecting its icon shows a fullscreen artwork carousel. Press Up to enter it, then Select to reveal Play and More Info.

The carousel contains up to eight items: Continue Watching first, then Next Up, then recent unwatched additions. Episodes from the same series share one slot. Play fetches the current resume position and starts playback; More Info opens the item page. Both actions support a cold app launch.

Alphane refreshes the shelf after sign-in, playback stops, watched-state changes, and Home refreshes. The extension reads cached artwork and metadata without receiving credentials or contacting the server. Signing out or switching users clears the cache. Missing content and snapshots older than seven days fall back to the static Alphane logo.

## Signing

The tvOS app and its embedded Top Shelf extension use the same App Group. For a custom build, put the following in the ignored `XcodeConfig/DevelopmentTeam.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
ALPHANE_BUNDLE_IDENTIFIER = com.example.alphane
PRODUCT_BUNDLE_IDENTIFIER = $(ALPHANE_BUNDLE_IDENTIFIER)
```

The extension identifier becomes `com.example.alphane.topshelf`; its shared container is `group.com.example.alphane`. Automatic signing provisions both targets. The signing team must support App Groups.

For simulator builds, override `ALPHANE_BUNDLE_IDENTIFIER` rather than globally overriding `PRODUCT_BUNDLE_IDENTIFIER`, so the app and extension keep distinct identifiers.
