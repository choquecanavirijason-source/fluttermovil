# Static closed-lid history regression

Run ./run_checks.ps1 with kotlinc and java. Compiles the actual curve and selection code with minimal ImagePoint/config fixtures. Verifies that a sustained measured closed contour is independent of which open-eye curve preceded it, works without any previous open contour, updates when a different closed contour arrives, and leaves open-eye geometry unchanged. The first 100 ms retain the existing transient weight; by 250 ms a continuous valid closed contour fully replaces the held arc.

This is shape-selection logic only. It does not validate landmark accuracy, camera projection, correct closed-eye classification, transient blink realism, or tracking behavior on a device.
