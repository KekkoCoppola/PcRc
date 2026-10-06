import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../controllers/pc_controller.dart';
import '../models/managed_app.dart';
import '../services/remote_control_service.dart';
import '../widgets/ambient_background.dart';
import '../widgets/app_card.dart';
import '../widgets/off_controls.dart';
import '../widgets/pc_case_hero.dart';
import '../widgets/power_card.dart';
import '../widgets/sleek_outline_button.dart';

class HomeScreen extends StatefulWidget {
  /// [controller] serve ai test; di default parla con Firebase e Home Assistant
  /// usando la configurazione di secrets.json.
  const HomeScreen({super.key, this.controller});

  final PcController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final PcController _pc;
  late final StreamSubscription<PcMessage> _messages;
  bool _refreshing = false;

  // Transizione tra controlli da spento (0.0) e dashboard da acceso (1.0)
  late final AnimationController _transition;
  late final Animation<double> _fadeOffScreen;
  late final Animation<double> _scaleOffScreen;
  late final Animation<double> _fadeHomeScreen;
  late final Animation<Offset> _slideHomeScreen;

  @override
  void initState() {
    super.initState();
    _pc = widget.controller ??
        PcController(
          RemoteControlService(AppConfig.fromEnvironment),
          configured: AppConfig.fromEnvironment.isComplete,
        );

    _transition = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _fadeOffScreen = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _transition, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );
    _scaleOffScreen = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _transition, curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic)),
    );
    _fadeHomeScreen = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _transition, curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic)),
    );
    _slideHomeScreen = Tween<Offset>(begin: const Offset(0.0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: _transition, curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic)),
    );

    _pc.addListener(_onPcChanged);
    _messages = _pc.messages.listen((m) => _showSnack(m.text, isError: m.isError));
    _pc.start();
  }

  @override
  void dispose() {
    _pc.removeListener(_onPcChanged);
    _messages.cancel();
    _pc.dispose();
    _transition.dispose();
    super.dispose();
  }

  void _onPcChanged() {
    if (!mounted) return;
    setState(() {});
    final status = _transition.status;
    if (_pc.dashboardVisible) {
      if (status != AnimationStatus.forward && status != AnimationStatus.completed) {
        _transition.forward();
      }
    } else if (status != AnimationStatus.reverse && status != AnimationStatus.dismissed) {
      _transition.reverse();
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _pc.refresh();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _onPowerTap() async {
    final result = await _pc.powerOn();
    if (result != PowerOnResult.needsPlugCycle || !mounted) return;
    final cycle = await _confirm(
      icon: Icons.power_rounded,
      color: const Color(0xFF00E5FF),
      title: 'Presa già accesa',
      body: 'La presa risulta accesa ma il PC non risponde, di solito perché è stato spento '
          'da Windows. La spengo e la riaccendo per farlo ripartire?\n\n'
          'Se il PC fosse acceso ma senza agent, verrebbe spento di colpo.',
      confirmLabel: 'RIAVVIA PRESA',
    );
    if (cycle) await _pc.powerOn(cyclePlug: true);
  }

  Future<void> _onShutdownTap() async {
    final confirm = await _confirm(
      icon: Icons.power_settings_new_rounded,
      color: const Color(0xFFEF4444),
      title: 'Spegnere il PC?',
      body: 'Windows si spegne e chiude tutte le app. A spegnimento completato '
          'la presa viene staccata.',
      confirmLabel: 'SPEGNI PC',
    );
    if (confirm) await _pc.shutdown();
  }

  Future<bool> _confirm({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF262B38), width: 1.2),
        ),
        title: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(body, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SleekOutlineButton(
            height: 40,
            borderWidth: 1.1,
            borderColor: const Color(0xFF475569),
            textColor: const Color(0xFFCBD5E1),
            label: 'ANNULLA',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(width: 8),
          SleekOutlineButton(
            height: 40,
            borderWidth: 1.3,
            borderColor: color,
            textColor: color,
            label: confirmLabel,
            icon: Icon(icon, size: 16),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String text, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
        backgroundColor: isError ? const Color(0xFF7F1D1D) : const Color(0xFF131722),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isError ? const Color(0xFFEF4444) : const Color(0xFF2E3547),
            width: 1,
          ),
        ),
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  /// Larghezza minima per affiancare PC e controlli (tablet / telefono in orizzontale).
  static const double _wideLayoutMinWidth = 720;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090C),
      body: PcRcAmbientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideLayoutMinWidth &&
                  constraints.maxWidth > constraints.maxHeight;
              return wide ? _buildWideLayout() : _buildColumnLayout(constraints);
            },
          ),
        ),
      ),
    );
  }

  /// Telefono e tablet in verticale: PC centrato in alto, controlli sotto.
  Widget _buildColumnLayout(BoxConstraints constraints) {
    final heroHeight = math.min(
      (constraints.maxHeight * 0.42).clamp(220.0, 480.0),
      (constraints.maxWidth - 40) / PcCaseHero.widthFor(1),
    );

    return _buildRefreshableScroll(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Center(child: PcCaseHero(poweredOn: _pc.ledsOn, height: heroHeight)),
          ),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _buildControls(math.min(constraints.maxWidth, 600)),
            ),
          ),
        ),
      ],
    );
  }

  /// Tablet in orizzontale: PC a sinistra, controlli a destra.
  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final heroHeight = math.min(
                math.min(constraints.maxHeight * 0.92, 640.0),
                constraints.maxWidth / PcCaseHero.widthFor(1),
              );
              return Center(child: PcCaseHero(poweredOn: _pc.ledsOn, height: heroHeight));
            },
          ),
        ),
        Expanded(
          flex: 6,
          child: LayoutBuilder(
            builder: (context, constraints) => _buildRefreshableScroll(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: _buildControls(constraints.maxWidth),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Aggiornamento trascinando verso il basso, solo con la dashboard visibile.
  Widget _buildRefreshableScroll({required List<Widget> slivers}) {
    return RefreshIndicator(
      onRefresh: _pc.refresh,
      notificationPredicate: (notification) =>
          _pc.dashboardVisible && defaultScrollNotificationPredicate(notification),
      color: const Color(0xFF00E5FF),
      backgroundColor: const Color(0xFF12141C),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: slivers,
      ),
    );
  }

  /// Controlli sotto il PC: power button da spento, dashboard da acceso,
  /// in dissolvenza incrociata guidata da [_transition].
  Widget _buildControls(double width) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AnimatedBuilder(
          animation: _transition,
          builder: (context, child) {
            final opacity = _fadeOffScreen.value;
            if (opacity <= 0.001) return const SizedBox.shrink();
            return IgnorePointer(
              ignoring: _transition.value > 0.4,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(scale: _scaleOffScreen.value, child: child),
              ),
            );
          },
          child: OffControls(controller: _pc, width: width, onPowerTap: _onPowerTap),
        ),
        AnimatedBuilder(
          animation: _transition,
          builder: (context, child) {
            final opacity = _fadeHomeScreen.value;
            if (opacity <= 0.001) return const SizedBox.shrink();
            return IgnorePointer(
              ignoring: _transition.value < 0.3,
              child: Opacity(
                opacity: opacity,
                child: SlideTransition(position: _slideHomeScreen, child: child),
              ),
            );
          },
          child: _buildDashboard(),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    final online = _pc.phase == PcPhase.online;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: PowerCard(
            controller: _pc,
            onShutdown: _onShutdownTap,
            onRefresh: _refresh,
            refreshing: _refreshing,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Row(
                  children: [
                    Icon(Icons.layers_outlined, size: 18, color: Color(0xFF94A3B8)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Applicazioni & Processi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${managedApps.length} monitorati',
                style: TextStyle(
                  color: const Color(0xFF64748B).withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        for (final app in managedApps)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: AppCard(
              app: app,
              info: _pc.app(app.key),
              online: online,
              busy: _pc.isBusy(app.key),
              onToggle: () => _pc.toggleApp(app.key),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Text(
            _pc.reachable
                ? 'Aggiornamento ogni 3 s • Firebase & Home Assistant'
                : 'Firebase non raggiungibile • riprovo ogni 3 s',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _pc.reachable
                  ? const Color(0xFF475569).withValues(alpha: 0.8)
                  : const Color(0xFFFCA5A5),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
