import 'package:flutter/material.dart';

import 'pc_led_painter.dart';

/// Foto del PC con la striscia LED RGB che segue [poweredOn]:
/// - spento -> acceso: la striscia si accende dall'alto verso il basso
///   (scintilla in testa), poi l'arcobaleno scorre in loop;
/// - acceso -> spento: dissolvenza;
/// - montato gia' acceso, o con animazioni ridotte: niente accensione animata.
class PcCaseHero extends StatefulWidget {
  const PcCaseHero({super.key, required this.poweredOn, required this.height});

  static const String asset = 'assets/images/pc_case.webp';

  /// Durata dell'accensione animata della striscia.
  static const Duration ignitionDuration = Duration(milliseconds: 1400);

  final bool poweredOn;
  final double height;

  /// Larghezza del box per [height]: foto + margine laterale per i riflessi.
  static double widthFor(double height) =>
      height * PcLedGeometry.imageHeightFraction * PcLedGeometry.aspectRatio * 1.2;

  @override
  State<PcCaseHero> createState() => _PcCaseHeroState();
}

class _PcCaseHeroState extends State<PcCaseHero> with TickerProviderStateMixin {
  static const _revealCurve = Interval(0.0, 0.65, curve: Curves.easeInOutCubic);
  static const _ambientCurve = Interval(0.45, 1.0, curve: Curves.easeOut);
  static const _sparkFadeCurve = Interval(0.65, 0.8);

  late final AnimationController _ignition = AnimationController(
    vsync: this,
    duration: PcCaseHero.ignitionDuration,
  );
  late final AnimationController _level = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  late final ImageStreamListener _imageListener = ImageStreamListener(_onImage);

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (widget.poweredOn) {
      _ignition.value = 1;
      _level.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncFlow();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant PcCaseHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.poweredOn == oldWidget.poweredOn) return;
    widget.poweredOn ? _turnOn() : _turnOff();
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageListener);
    _imageInfo?.dispose();
    _ignition.dispose();
    _level.dispose();
    _flow.dispose();
    super.dispose();
  }

  void _turnOn() {
    _level.value = 1;
    if (_reduceMotion) {
      _ignition.value = 1;
    } else {
      _ignition.forward(from: 0);
    }
    _syncFlow();
  }

  void _turnOff() {
    if (_reduceMotion) {
      _level.value = 0;
      _ignition.value = 0;
      _syncFlow();
      return;
    }
    _level.reverse().whenCompleteOrCancel(() {
      // Riacceso durante la dissolvenza: _turnOn ha gia' sistemato tutto.
      if (!mounted || widget.poweredOn) return;
      _ignition.value = 0;
      _syncFlow();
    });
  }

  /// Il loop dell'arcobaleno gira solo mentre la striscia e' visibile.
  void _syncFlow() {
    final shouldFlow = !_reduceMotion && (widget.poweredOn || _level.value > 0);
    if (shouldFlow && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!shouldFlow && _flow.isAnimating) {
      _flow.stop();
    }
  }

  void _resolveImage() {
    final stream = const AssetImage(PcCaseHero.asset)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _imageStream?.key) return;
    _imageStream?.removeListener(_imageListener);
    _imageStream = stream..addListener(_imageListener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    setState(() {
      _imageInfo?.dispose();
      _imageInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _imageInfo?.image;

    return Semantics(
      image: true,
      label: widget.poweredOn ? 'PC acceso' : 'PC spento',
      child: RepaintBoundary(
        child: SizedBox(
          width: PcCaseHero.widthFor(widget.height),
          height: widget.height,
          child: image == null
              ? null
              : AnimatedBuilder(
                  animation: Listenable.merge([_ignition, _level, _flow]),
                  builder: (context, _) {
                    final t = _ignition.value;
                    return CustomPaint(
                      painter: PcLedPainter(
                        image: image,
                        reveal: _revealCurve.transform(t),
                        intensity: _level.value,
                        ambient: _ambientCurve.transform(t),
                        spark: t < 1 ? 1 - _sparkFadeCurve.transform(t) : 0,
                        hueShift: _flow.value,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
