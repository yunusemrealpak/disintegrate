import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'disintegrate_program.dart';

/// Paints [child] partway through a disintegration.
///
/// This is the plumbing: it turns a single `0..1` value into the effect and
/// does nothing else. Drive [progress] from whatever already owns the timeline
/// - an `AnimationController`, a scroll offset, a drag - so that a screenful of
/// these can share one animation instead of running one controller each.
///
/// Use [Disintegrate] instead when a widget should simply dissolve itself.
class DisintegrateEffect extends StatefulWidget {
  const DisintegrateEffect({
    super.key,
    required this.progress,
    this.drift = const Offset(64, -44),
    this.particleSize = 3,
    this.sweep = 0.35,
    this.turbulence = 22,
    this.seed = 0,
    this.spread = EdgeInsets.zero,
    required this.child,
  });

  /// 0 leaves [child] untouched, 1 has carried all of it away.
  final double progress;

  /// Where the dust goes, and how far, in logical pixels.
  final Offset drift;

  /// Particle size in logical pixels. Smaller reads as dust, larger as debris.
  final double particleSize;

  /// 0 dissolves the whole surface at once; 1 sweeps it across [drift].
  final double sweep;

  /// How far particles wander sideways, in logical pixels.
  final double turbulence;

  /// Changes which particles leave first. Two widgets with the same seed
  /// dissolve identically, which is rarely what you want in a list.
  final double seed;

  /// Room for the dust to travel into, around [child].
  ///
  /// A shader filter cannot paint outside the surface it is handed, so without
  /// this the dust is cut off at the child's own edge and the drift has nowhere
  /// to go. This is padding, so it does take up layout space - the usual move
  /// is to spend the gap the layout already had between items.
  final EdgeInsets spread;

  final Widget child;

  @override
  State<DisintegrateEffect> createState() => _DisintegrateEffectState();
}

class _DisintegrateEffectState extends State<DisintegrateEffect> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    final ui.FragmentProgram? program = DisintegrateProgram.cached;
    if (program != null) {
      _shader = program.fragmentShader();
      return;
    }
    DisintegrateProgram.preload().then(
      (ui.FragmentProgram program) {
        if (!mounted) {
          return;
        }
        setState(() => _shader = program.fragmentShader());
      },
      // A backend without shader filters, or a bundle without the asset. The
      // fallback below already covers it, so this must not surface as an error.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double progress = widget.progress;

    // An untouched widget must cost nothing: no filter, no shader, no extra
    // layer. The effect only enters the tree once it has something to do.
    if (progress <= 0.0) {
      return Padding(padding: widget.spread, child: widget.child);
    }
    if (progress >= 1.0) {
      // Keep it laid out and keep its state, but stop painting it. Opacity
      // short-circuits at zero, so this is cheaper than running the shader to
      // produce an empty surface.
      return Opacity(
        opacity: 0,
        child: IgnorePointer(
          child: Padding(padding: widget.spread, child: widget.child),
        ),
      );
    }

    final ui.FragmentShader? shader = _shader;
    if (shader == null || !DisintegrateProgram.isSupported) {
      // Still loading, or a backend without shader filters. Fading is not the
      // effect, but it is the same beginning and end, so nothing jumps.
      return Opacity(
        opacity: 1.0 - progress,
        child: IgnorePointer(
          child: Padding(padding: widget.spread, child: widget.child),
        ),
      );
    }

    // The shader works in physical pixels because that is what FlutterFragCoord
    // reports; authoring in logical pixels and converting here keeps particle
    // size consistent across devices instead of scaling with the screen.
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int slot = DisintegrateProgram.firstFloatSlot(shader);
    shader
      ..setFloat(slot + 0, progress)
      ..setFloat(slot + 1, widget.drift.dx * dpr)
      ..setFloat(slot + 2, widget.drift.dy * dpr)
      ..setFloat(slot + 3, widget.particleSize * dpr)
      ..setFloat(slot + 4, widget.sweep.clamp(0.0, 1.0))
      ..setFloat(slot + 5, widget.turbulence * dpr)
      ..setFloat(slot + 6, widget.seed);

    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.shader(shader),
        child: Padding(padding: widget.spread, child: widget.child),
      ),
    );
  }
}

/// Dissolves [child] when [visible] turns false, and puts it back when it turns
/// true again.
///
/// Owns one [AnimationController]. When several widgets dissolve together -
/// a list reacting to a single action - drive [DisintegrateEffect] from one
/// shared animation instead, and give each item its own slice of it.
class Disintegrate extends StatefulWidget {
  const Disintegrate({
    super.key,
    required this.visible,
    required this.child,
    this.duration = const Duration(milliseconds: 1100),
    this.reverseDuration,
    this.curve = Curves.easeInCubic,
    this.reverseCurve = Curves.easeOutCubic,
    this.drift = const Offset(64, -44),
    this.particleSize = 3,
    this.sweep = 0.35,
    this.turbulence = 22,
    this.seed = 0,
    this.spread = EdgeInsets.zero,
    this.onDissolved,
    this.onRestored,
  });

  final bool visible;
  final Widget child;
  final Duration duration;
  final Duration? reverseDuration;

  /// Applied while dissolving. The default accelerates, so the surface holds
  /// its shape for a moment before it goes - a linear dissolve reads as a wipe.
  final Curve curve;

  /// Applied while coming back. Reassembling is not the dissolve played
  /// backwards: it decelerates into place.
  final Curve reverseCurve;

  final Offset drift;
  final double particleSize;
  final double sweep;
  final double turbulence;
  final double seed;

  /// See [DisintegrateEffect.spread].
  final EdgeInsets spread;

  final VoidCallback? onDissolved;
  final VoidCallback? onRestored;

  @override
  State<Disintegrate> createState() => _DisintegrateState();
}

class _DisintegrateState extends State<Disintegrate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.reverseDuration ?? widget.duration,
    value: widget.visible ? 0.0 : 1.0,
  )..addStatusListener(_handleStatus);

  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
    reverseCurve: widget.reverseCurve,
  );

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onDissolved?.call();
    } else if (status == AnimationStatus.dismissed) {
      widget.onRestored?.call();
    }
  }

  @override
  void didUpdateWidget(Disintegrate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    _controller.reverseDuration = widget.reverseDuration ?? widget.duration;
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _controller.reverse() : _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The child is passed through so it is built once, not once per frame of
    // the dissolve.
    return ListenableBuilder(
      listenable: _progress,
      builder: (BuildContext context, Widget? child) => DisintegrateEffect(
        progress: _progress.value,
        drift: widget.drift,
        particleSize: widget.particleSize,
        sweep: widget.sweep,
        turbulence: widget.turbulence,
        seed: widget.seed,
        spread: widget.spread,
        child: child!,
      ),
      child: widget.child,
    );
  }
}
