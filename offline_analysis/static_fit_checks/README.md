# Static band/contour coordinate fit

Runs the real bender against flat, shallow and rounded synthetic contours. For a frontal eye, the displayed band is WIDTH_MULTIPLIER times the eye width. Checks that the requested curve is sampled at that displayed X coordinate rather than the unexpanded X coordinate. The fixture reproduced a 3.65 image-pixel error on a strongly rounded contour before the correction and less than 0.00002 px numerical error afterward.

Run ./run_checks.ps1. Uses fixtures from ../root_pivot_checks and the cached kotlin-math jar. This verifies the frontal coordinate mapping, not landmark accuracy, camera calibration, arbitrary head angles, or visual fit on real people.
