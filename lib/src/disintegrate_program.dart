import 'dart:ui' as ui;

/// Loads and caches the disintegration fragment program.
///
/// A [ui.FragmentProgram] is expensive to build and there is only ever one
/// shader here, so it is loaded once per isolate and shared. [preload] exists
/// so an app can pay that cost during start-up instead of on the first frame
/// of the effect, which would otherwise fall back to a plain fade.
abstract final class DisintegrateProgram {
  static const String _asset = 'packages/disintegrate/shaders/disintegrate.frag';

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram>? _pending;

  /// The program, or null while it is still loading.
  static ui.FragmentProgram? get cached => _program;

  /// Whether this device can run the effect at all.
  ///
  /// Shader-backed [ui.ImageFilter]s are an Impeller feature; on other backends
  /// the widgets degrade to an opacity fade rather than throwing.
  static bool get isSupported => ui.ImageFilter.isShaderFilterSupported;

  static Future<ui.FragmentProgram> preload() {
    final ui.FragmentProgram? loaded = _program;
    if (loaded != null) {
      return Future<ui.FragmentProgram>.value(loaded);
    }
    return _pending ??= ui.FragmentProgram.fromAsset(_asset).then(
      (ui.FragmentProgram program) {
        _program = program;
        _pending = null;
        return program;
      },
      onError: (Object error, StackTrace stack) {
        // Clearing the slot lets a later caller try again rather than inheriting
        // a permanently rejected future.
        _pending = null;
        throw Error.throwWithStackTrace(error, stack);
      },
    );
  }

  /// Float slot of the first authored uniform.
  ///
  /// The engine-provided `vec2 uSize` occupies the first two slots, but that
  /// has not been stable across engine versions, so it is probed once against a
  /// real shader rather than assumed: writing past the end throws, and that
  /// tells us the layout.
  static int? _firstFloatSlot;

  static int firstFloatSlot(ui.FragmentShader shader) {
    int? slot = _firstFloatSlot;
    if (slot != null) {
      return slot;
    }
    // Seven authored floats: progress, drift.xy, cell, sweep, turbulence, seed.
    try {
      shader.setFloat(8, 0);
      slot = 2;
    } on Object {
      slot = 0;
    }
    return _firstFloatSlot = slot;
  }
}
