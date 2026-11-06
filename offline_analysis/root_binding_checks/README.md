# Root projection regression

The checks compile actual CameraProjection, LashRootBinding, LashMeshBender, LashRootDepth and LidDropRotation with minimal JVM geometry/config fixtures. Check.kt covers camera unprojection through inverse final model transform, the real bender, the final model transform and pixel projection. Tests open/closed/flat/round contours, nonuniform scales, reversed orientations and preserved fiber offsets. Synthetic maximum observed error: 0.000063 image pixels.

AssetCheck.kt accepts a directory of little-endian XYZ float position fixtures extracted from the GLB assets (no header). It tests actual base-row vertices under open/closed transforms. All 12 repository GLBs passed a 2-pixel bound; worst observed: 0.330 pixels.

These are geometric projection tests. They do not verify landmarks, GPU upload scheduling, or apparent fit in the running phone. Keep the green reference and magenta material until visual confirmation. SourceRootDepth uses a sampled base-row depth profile; residual thickness/profile approximation accounts for the nonzero real-asset error.

BulkCheck.kt compares direct component writes against reusable heap staging plus bulk FloatBuffer writes. All 55,704,012 position/tangent floats matched bit for bit across the 12 assets with open/intermediate/closed eyes, binding on/off and mesh smoothing on/off. Also checks unchanged buffer cursors and storage reuse. This is equivalence evidence; improvement in Android frame rate still requires a device measurement at comparable temperature.
