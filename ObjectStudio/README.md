# Object Studio 2.0

Native iOS image studio with on-device cutouts, remote depth and image-angle generation, GLB preview and local USDZ conversion.

## Changes
- Resolve Gradio input ordering and defaults from live `/gradio_api/info` or legacy `/info`.
- Only fall back after a missing submission route; never restart an accepted GPU job after a result error.
- Use Qwen's image-component endpoint (`infer_and_show_video_button`), which returns downloadable ImageData rather than the API-only PIL metadata response.
- Reduce Hunyuan chunks from 200000 to its live default of 8000.
- Load GLB using pinned GLTFKit2 0.5.15 and preview with SceneKit; export USDZ locally and reuse existing models for AR.
- Separate image editing, generation and results, show persistent task progress, preserve endpoint settings and downloaded outputs.

## Build and verification
Run `xcodegen generate` in this directory, then build the ObjectStudio scheme with Xcode 16 or later. Run ObjectStudioTests on an iOS simulator before packaging.

The live Hunyuan and Qwen schemas were retrieved and inspected on September 5, 2026. No authenticated GPU generation or iPhone runtime test has yet been performed for this revision. GPU quota and Space availability remain provider-dependent. Swift compilation and simulator tests await the macOS CI run. SceneKit may not preserve every advanced glTF material extension.
