class_name HudScale
extends RefCounted
## _shared/UI_LAYOUT.md §1 (final): author everything in 720p design space.
## Every CSS value in the layout table is multiplied by K = 720 / 390 ≈ 1.846.
## The logical viewport height is always 720 (canvas_items + expand), so K is a constant —
## never derive it from the runtime/physical window height (that shrank the HUD 3-4x on device).

const K := 720.0 / 390.0

static func factor() -> float:
	return K
