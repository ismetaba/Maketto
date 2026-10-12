import SwiftUI

/// Canvas wrapper whose zoom/pan participate in SwiftUI animation, so
/// `withAnimation` camera changes (zoom buttons, "fit") glide instead of
/// snapping. Gesture-driven changes happen outside `withAnimation` and stay
/// 1:1 with the finger.
///
/// Because `PlanCamera.setZoom` scales the pan proportionally with the zoom,
/// linear interpolation of (zoom, pan) preserves the view-centre-fixed zoom
/// law on every intermediate frame — the tween is geometrically exact.
struct AnimatedPlanCanvas: View, Animatable {
    var zoom: CGFloat
    var pan: CGSize
    var draw: (GraphicsContext, CGSize, CGFloat, CGSize) -> Void

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(zoom, AnimatablePair(pan.width, pan.height)) }
        set {
            zoom = newValue.first
            pan = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        Canvas { context, size in draw(context, size, zoom, pan) }
    }
}
