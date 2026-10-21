/// Toggle for the on-screen GPS/report debug overlay on the match screen.
/// Deliberately not gated by kDebugMode: it needs to work in release builds
/// installed on real devices during field testing. Flip to false to hide it.
const bool showGpsDebug = true;
