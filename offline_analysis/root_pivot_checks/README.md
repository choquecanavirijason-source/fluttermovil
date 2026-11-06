# Root attachment during blinking

Compiles the actual LashMeshBender, LashLineCurve and LashRootDepth with small JVM geometry/configuration stubs. Run `./run_checks.ps1` with kotlinc and java installed and kotlin-math cached.

The synthetic asset includes a nonzero curved root Z profile. Covers straight and rounded lid contours, both rotation signs from -150 to +150 degrees (including 90), four unequal Y/Z scale ratios, and depth wrapping on/off. Checks that world-space roots remain on the requested contour, that open root geometry stays unchanged, and that fibers retain their length and drop about their own roots.

This verifies the geometry mathematics. It does not establish MediaPipe landmark accuracy, visual realism, rear/front-camera parity, GPU upload timing, or fit on every face. Device comparison is still required. Test configuration constants are fixed fixtures in Types.kt.
