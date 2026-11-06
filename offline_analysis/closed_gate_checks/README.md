# Closed contour availability regression

Fixture geometric ratios come from the phone log while a closed-eye portrait was held visible. The actual OpennessTracker keeps the eye closed throughout these samples, but the former independent normalizedOpenness < 0.3 contour gate dropped 3 of 8 measurements. This reset the measured-contour settling timer and let the held open arc return.

Compiles actual OpennessTracker, ClosedLidContour and LashLineCurve. Verifies the current contour stays available through those fluctuations, settles fully to the measured line, and reopening returns to the unchanged open branch. Types.kt contains fixed configuration fixtures. Run ./run_checks.ps1 with kotlinc/java.

This establishes the gating/selection fix, not pixel alignment of the 3D mesh; compare the green detection and magenta band on device.
