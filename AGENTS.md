# AGENTS.md

- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.

## Updating from Swiftfin

- Fetch the official `jellyfin/Swiftfin` repository through the `upstream` remote and merge `upstream/main` into Alphane. Preserve the upstream commit history with a real merge commit.
- Do not replace an upstream merge with handwritten reimplementations, selective backports, or cherry-picks.
- Review the incoming changes against Alphane's existing behavior and tests, especially Home discovery, playback completion, episode continuation, focus restoration, navigation, branding, and Top Shelf.
- Discard upstream changes that break Alphane's behavior. Record the rejected changes and the concrete regression in the merge commit message.
- Resolve merge conflicts by retaining compatible upstream improvements and Alphane's custom behavior. Keep Alphane project paths, module names, and branding, along with Swiftfin's licensing and attribution.
- Build and run the Apple TV regression tests before finishing the merge. Verify that the upstream revision is an ancestor of the completed merge and that no conflicts remain.
- Never force-push or rewrite already published history to incorporate upstream changes. Deploy only when requested.
