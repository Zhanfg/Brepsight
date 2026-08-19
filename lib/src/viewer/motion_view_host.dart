import 'dart:async';

import 'package:cad_engine/cad_engine.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Adds an opt-in, bounded gyroscope offset around the current CAD camera.
///
/// The offset is deliberately temporary. Before any pointer interaction it is
/// reversed so native camera state is back in sync with the Viewer's precise
/// Dart camera state used by picking/measurement. This keeps motion navigation
/// a presentation input rather than a geometry/selection state mutation.
class MotionViewHost extends StatefulWidget {
  const MotionViewHost({
    super.key,
    required this.enabled,
    required this.sensitivity,
    required this.recenterToken,
    required this.child,
    this.onSensorUnavailable,
  });

  final bool enabled;
  final double sensitivity;
  final int recenterToken;
  final Widget child;
  final VoidCallback? onSensorUnavailable;

  @override
  State<MotionViewHost> createState() => _MotionViewHostState();
}

class _MotionViewHostState extends State<MotionViewHost> {
  StreamSubscription<GyroscopeEvent>? _subscription;
  DateTime? _lastSampleAt;
  DateTime _resumeAfter = DateTime.fromMillisecondsSinceEpoch(0);
  double _yawOffset = 0;
  double _pitchOffset = 0;
  bool _reportedUnavailable = false;

  static const double _nativeRadiansPerOrbitUnit = 0.010;
  static const double _maxOffset = 0.42;
  static const double _maxStep = 0.045;
  static const double _deadZone = 0.018;

  @override
  void initState() {
    super.initState();
    _syncSubscription();
  }

  @override
  void didUpdateWidget(covariant MotionViewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recenterToken != widget.recenterToken) {
      unawaited(_restoreNeutral());
    }
    if (oldWidget.enabled != widget.enabled) {
      _syncSubscription();
    }
  }

  void _syncSubscription() {
    if (!widget.enabled) {
      unawaited(_stopMotion());
      return;
    }
    if (_subscription != null) return;
    _reportedUnavailable = false;
    _lastSampleAt = null;
    _subscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      _onGyroscope,
      onError: (_) {
        if (_reportedUnavailable) return;
        _reportedUnavailable = true;
        widget.onSensorUnavailable?.call();
        unawaited(_stopMotion());
      },
      cancelOnError: true,
    );
  }

  void _onGyroscope(GyroscopeEvent event) {
    if (!widget.enabled) return;
    final now = event.timestamp;
    final previous = _lastSampleAt;
    _lastSampleAt = now;
    if (previous == null || DateTime.now().isBefore(_resumeAfter)) return;

    final seconds = now.difference(previous).inMicroseconds / 1000000.0;
    if (seconds <= 0 || seconds > 0.12) return;

    double filtered(double value) => value.abs() < _deadZone ? 0 : value;

    // Portrait phone coordinates: y angular velocity gives a natural
    // left/right orbit; x gives up/down orbit. Ignore z so rotating the phone
    // flat in the hand does not spin the model unexpectedly.
    final yawStep = (-filtered(event.y) * seconds * widget.sensitivity)
        .clamp(-_maxStep, _maxStep)
        .toDouble();
    final pitchStep = (-filtered(event.x) * seconds * widget.sensitivity)
        .clamp(-_maxStep, _maxStep)
        .toDouble();

    final nextYaw = (_yawOffset + yawStep).clamp(-_maxOffset, _maxOffset).toDouble();
    final nextPitch = (_pitchOffset + pitchStep).clamp(-_maxOffset, _maxOffset).toDouble();
    final appliedYaw = nextYaw - _yawOffset;
    final appliedPitch = nextPitch - _pitchOffset;
    if (appliedYaw.abs() < 1e-6 && appliedPitch.abs() < 1e-6) return;

    _yawOffset = nextYaw;
    _pitchOffset = nextPitch;
    unawaited(
      CadEngine.instance.orbit(
        appliedYaw / _nativeRadiansPerOrbitUnit,
        appliedPitch / _nativeRadiansPerOrbitUnit,
      ),
    );
  }

  Future<void> _restoreNeutral() async {
    if (_yawOffset.abs() > 1e-6 || _pitchOffset.abs() > 1e-6) {
      final yaw = _yawOffset;
      final pitch = _pitchOffset;
      _yawOffset = 0;
      _pitchOffset = 0;
      await CadEngine.instance.orbit(
        -yaw / _nativeRadiansPerOrbitUnit,
        -pitch / _nativeRadiansPerOrbitUnit,
      );
    }
    _lastSampleAt = null;
  }

  Future<void> _stopMotion() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _restoreNeutral();
  }

  void _onPointerDown(PointerDownEvent _) {
    // Reconcile with the exact camera before the child sees a measurement,
    // selection, pan, orbit, edit or command interaction.
    _resumeAfter = DateTime.now().add(const Duration(milliseconds: 650));
    unawaited(_restoreNeutral());
  }

  @override
  void dispose() {
    final subscription = _subscription;
    _subscription = null;
    subscription?.cancel();
    if (_yawOffset.abs() > 1e-6 || _pitchOffset.abs() > 1e-6) {
      unawaited(
        CadEngine.instance.orbit(
          -_yawOffset / _nativeRadiansPerOrbitUnit,
          -_pitchOffset / _nativeRadiansPerOrbitUnit,
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: widget.child,
    );
  }
}
