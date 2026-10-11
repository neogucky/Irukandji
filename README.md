<p align="center">
  <img alt="Alphane" src="./Resources/Branding/Alphane-wordmark.png" width="360">
</p>

# Alphane

Alphane is a Jellyfin client for Apple TV and iOS, with a charcoal interface, direct navigation, and improved episode continuation.

This fork is based on [Swiftfin](https://github.com/jellyfin/Swiftfin), built by Jellyfin and its contributors. It uses SwiftUI with native and VLC playback engines.

To build locally, open `Alphane.xcodeproj` and select the existing `Alphane tvOS` or `Alphane` scheme. Signing overrides belong in the ignored `XcodeConfig/DevelopmentTeam.xcconfig` file.

Report issues or follow development in [this repository](https://github.com/neogucky/Irukandji).

Alphane retains Swiftfin's [Mozilla Public License 2.0](LICENSE.md) and original source attribution. See [Documentation](Documentation) for the inherited development and playback documentation.

The Xcode project, app modules, and local packages use the Alphane name. `Shared/Services/UpstreamCompatibility.swift` contains the legacy Swiftfin storage identifiers needed to migrate existing profiles, settings, and custom artwork. The app keeps its bundle identifier so installed updates retain Keychain access.
