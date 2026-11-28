# Scene checks

Run from the repository root on Windows with Chrome or Edge installed:

```powershell
powershell -ExecutionPolicy Bypass -File tests/check-scene.ps1
powershell -ExecutionPolicy Bypass -File tests/compare-scene.ps1
```

`check-scene.ps1` checks the current geometry, light sequencing, reverse scrolling,
occlusion, cache invalidation on resize and animation scheduling. It captures
the entrance, workshop, exit, river, canyon, dam outlets, ascent and crest at
390, 1024 and 1920 CSS pixels. Canyon checks cover solid dam occlusion,
clearance of the central ascent, visible outlet jets, flowing water at a stationary
camera, reverse travel and a stable reduced-motion state.

`compare-scene.ps1` loads the original scene from Git (`86e1636` by default),
renders both versions with an identical clock, and compares 15 frames per
viewport, including reverse travel. Software rendering requires identical RGBA
pixels. Object counts must also match. `-Reference <commit>` selects a different
baseline; the commit must contain the same scene structure.
Use `-VisualOnly` to skip benchmarks during a full visual regression run.

Reports and screenshots are written to a new directory under the system temp
directory. No browser profile or generated capture is added to the repository.

Useful optional checks:

```powershell
# Short comparison, including a high-density mobile viewport.
powershell -ExecutionPolicy Bypass -File tests/compare-scene.ps1 -Quick -Sizes '390,844' -DeviceScaleFactor 2
# GPU rendering: permits small antialiasing differences between renderer paths.
powershell -ExecutionPolicy Bypass -File tests/compare-scene.ps1 -Quick -Sizes '1024,768' -HardwareAcceleration
# JavaScript stage timings for one moving frame in the workshop.
powershell -ExecutionPolicy Bypass -File tests/compare-scene.ps1 -Profile -Sizes '1024,768'
# Run functional checks in Edge.
powershell -ExecutionPolicy Bypass -File tests/check-scene.ps1 -Browser 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
```

Timing rows report JavaScript submission time separately from completed
rasterization time, forced with a pixel readback. These are synchronous headless
benchmarks, not interactive FPS or a direct measurement of CPU/GPU power.
Readbacks can affect browser acceleration heuristics. Run comparisons without
other browser checks in parallel when collecting performance numbers.
