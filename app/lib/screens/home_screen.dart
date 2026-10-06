import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/app_info.dart';
import '../models/pc_status.dart';
import '../models/pending_command.dart';
import '../services/remote_control_service.dart';
import '../widgets/ambient_background.dart';
import '../widgets/pc_case_hero.dart';
import '../widgets/power_button_widget.dart';
import '../widgets/sleek_outline_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final RemoteControlService _service = RemoteControlService();

  PcStatus _pcStatus = PcStatus(fetchTime: DateTime.now());
  Map<String, AppInfo> _apps = {
    'claude': AppInfo(key: 'claude', displayName: 'Claude', actualState: 'STOPPED'),
    'antigravity':
        AppInfo(key: 'antigravity', displayName: 'Antigravity 2.0', actualState: 'STOPPED'),
  };

  // State flags
  final bool _isTurningOffPc = false;
  bool _isBooting = false;
  bool _isRefreshing = false;
  Timer? _pollingTimer;

  // Visual prototype mode: strictly visual, starts on PC Spento, no real shutdowns or process killing
  bool _simulatedOnline = false;

  bool get _isEffectiveOnline => _simulatedOnline;

  // Commands in flight per app (visual simulation)
  final Map<String, PendingCommand> _pending = {};
  final Set<String> _sending = {};
  bool _isBusy(String appKey) => _pending.containsKey(appKey) || _sending.contains(appKey);

  // Transition controller between PC Off (0.0) and PC On (1.0)
  late AnimationController _transitionController;
  late Animation<double> _fadeOffScreen;
  late Animation<double> _scaleOffScreen;
  late Animation<double> _fadeHomeScreen;
  late Animation<Offset> _slideHomeScreen;


  @override
  void initState() {
    super.initState();

    // Setup transition animations
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      value: 0.0, // Start initially at PC Off view (centered power button only)
    );

    _fadeOffScreen = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _scaleOffScreen = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _fadeHomeScreen = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _slideHomeScreen = Tween<Offset>(
      begin: const Offset(0.0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // Only read initial display names/read-only info without changing transition state
    _fetchDataReadOnly();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _transitionController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _fetchDataReadOnly() async {
    try {
      final futures = await Future.wait([
        _service.fetchPcStatus(),
        _service.fetchAppsStatus(),
      ]);

      if (!mounted) return;

      setState(() {
        _pcStatus = futures[0] as PcStatus;
        final appsMap = futures[1] as Map<String, AppInfo>;
        _apps = {
          for (final key in ['claude', 'antigravity'])
            key: appsMap[key] ?? _apps[key]!,
        };
      });
    } catch (_) {}
  }

  /// Click on the Power Button under the PC:
  /// 1. Ignites the neon cyan ring and the PC's RGB LED strip
  /// 2. Smooth fade-away of the power button and fade-in of the dashboard
  /// 3. Visual-only preview (NO actual commands sent)
  Future<void> _handlePowerButtonTap() async {
    if (_isBooting) return;

    setState(() {
      _isBooting = true;
    });

    // Let the user appreciate the LED strip lighting up along the case
    await Future.delayed(PcCaseHero.ignitionDuration);
    if (!mounted) return;

    // Transition smoothly to Home Screen
    setState(() {
      _simulatedOnline = true;
    });

    await _transitionController.forward();

    if (mounted) {
      setState(() {
        _isBooting = false;
      });
      _showSnack('Sistema avviato con successo. Dashboard attiva.', isError: false);
    }
  }

  /// Visual-only turn off PC: smoothly transitions back to off screen with centered power button
  Future<void> _turnOffPcWithConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF262B38), width: 1.2),
        ),
        title: Row(
          children: const [
            Icon(Icons.power_settings_new_rounded, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 10),
            Text(
              'Spegnere il PC?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'Simulazione visiva: l\'interfaccia tornerà alla schermata iniziale con il tasto di accensione centrale.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
        ),
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
            borderColor: const Color(0xFFEF4444),
            textColor: const Color(0xFFEF4444),
            label: 'SPEGNI PC',
            icon: const Icon(Icons.power_settings_new_rounded, size: 16),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _simulatedOnline = false;
    });

    // Smooth transition back to the single power button view
    await _transitionController.reverse();
  }


  /// Visual-only toggle for app state: simulates smooth state change without sending real commands
  Future<void> _toggleAppState(String appKey) async {
    final currentApp = _apps[appKey];
    if (currentApp == null || _isBusy(appKey)) return;

    final isCurrentlyRunning = currentApp.isRunning;
    final newState = isCurrentlyRunning ? 'STOPPED' : 'RUNNING';

    setState(() {
      _sending.add(appKey);
      _apps[appKey] = currentApp.copyWith(isMutating: true);
    });

    // Simulate smooth processing delay (~500ms)
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    setState(() {
      _sending.remove(appKey);
      _apps[appKey] = currentApp.copyWith(
        actualState: newState,
        isMutating: false,
      );
    });

    final action = newState == 'RUNNING' ? 'avviato' : 'arrestato';
    _showSnack('${currentApp.displayName}: processo $action (simulazione visiva)', isError: false);
  }

  Future<void> _fetchData({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() => _isRefreshing = true);
    }
    await _fetchDataReadOnly();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  void _showSnack(String text, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
        ),
        backgroundColor: isError ? const Color(0xFF7F1D1D) : const Color(0xFF131722),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isError ? const Color(0xFFEF4444) : const Color(0xFF2E3547),
            width: 1,
          ),
        ),
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  /// Larghezza minima per affiancare PC e controlli (tablet / telefono in orizzontale).
  static const double _wideLayoutMinWidth = 720;

  /// I LED partono appena arriva corrente, prima che il PC risulti online.
  bool get _pcPoweredOn => _isBooting || _isEffectiveOnline;

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
  /// Aggiornamento: trascinando verso il basso.
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
            child: Center(
              child: PcCaseHero(poweredOn: _pcPoweredOn, height: heroHeight),
            ),
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
              return Center(
                child: PcCaseHero(poweredOn: _pcPoweredOn, height: heroHeight),
              );
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

  Widget _buildRefreshableScroll({required List<Widget> slivers}) {
    return RefreshIndicator(
      onRefresh: () => _fetchData(showLoader: true),
      // Da spento non c'e' niente da aggiornare: niente pull-to-refresh.
      notificationPredicate: (notification) =>
          _isEffectiveOnline && defaultScrollNotificationPredicate(notification),
      color: const Color(0xFF00E5FF),
      backgroundColor: const Color(0xFF12141C),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: slivers,
      ),
    );
  }

  /// Controlli sotto il PC: power button da spento, dashboard da acceso,
  /// in dissolvenza incrociata guidata da [_transitionController].
  Widget _buildControls(double width) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AnimatedBuilder(
          animation: _transitionController,
          builder: (context, child) {
            final opacity = _fadeOffScreen.value;
            if (opacity <= 0.001) return const SizedBox.shrink();

            return IgnorePointer(
              ignoring: _transitionController.value > 0.4,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: _scaleOffScreen.value,
                  child: child,
                ),
              ),
            );
          },
          child: _buildOffControls(width),
        ),
        AnimatedBuilder(
          animation: _transitionController,
          builder: (context, child) {
            final opacity = _fadeHomeScreen.value;
            if (opacity <= 0.001) return const SizedBox.shrink();

            return IgnorePointer(
              ignoring: _transitionController.value < 0.3,
              child: Opacity(
                opacity: opacity,
                child: SlideTransition(
                  position: _slideHomeScreen,
                  child: child,
                ),
              ),
            );
          },
          child: _buildDashboardControls(),
        ),
      ],
    );
  }

  /// =========================================================================
  /// PC OFF CONTROLS (Power Button under the PC)
  /// =========================================================================
  Widget _buildOffControls(double width) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photorealistic Power Button
          PowerButtonWidget(
            size: (width * 0.32).clamp(120.0, 170.0),
            isOnline: _isEffectiveOnline,
            isBooting: _isBooting,
            onTap: _handlePowerButtonTap,
          ),

          const SizedBox(height: 16),

          // Clean status title
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _isBooting
                  ? 'AVVIO IN CORSO...'
                  : 'PC SPENTO',
              key: ValueKey<bool>(_isBooting),
              style: TextStyle(
                color: _isBooting ? const Color(0xFF00E5FF) : const Color(0xFFE2E8F0),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 3.5,
                shadows: _isBooting
                    ? [
                        const Shadow(
                          color: Color(0xFF00E5FF),
                          blurRadius: 16,
                        )
                      ]
                    : null,
              ),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _isBooting
                ? 'Invio impulso Home Assistant • Avvio in corso'
                : 'Tocca il pulsante per accendere il PC',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 18),

          // Last known state info chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1015),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1E232E), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history_rounded, size: 13, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Ultimo segnale: ${_pcStatus.formattedStatus}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Bottom subtle hint
          const Text(
            'Smart PC Controller • Powered by Home Assistant',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// =========================================================================
  /// DASHBOARD CONTROLS (status, power, apps) under the PC
  /// =========================================================================
  Widget _buildDashboardControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Power Control Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: _buildPowerControlCard(),
        ),

        // Applications Section Title
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
                '2 monitorati',
                style: TextStyle(
                  color: const Color(0xFF64748B).withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Claude App Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: _buildAppCard(
            app: _apps['claude']!,
            accentColor: const Color(0xFFD27354),
            iconAsset: 'assets/icons/claude.png',
            subtitle: 'Claude AI Desktop & Sessioni Code',
          ),
        ),

        // Antigravity 2.0 App Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: _buildAppCard(
            app: _apps['antigravity']!,
            accentColor: const Color(0xFFA855F7),
            iconAsset: 'assets/icons/antigravity.png',
            subtitle: 'Antigravity Coding Agent Daemon',
          ),
        ),

        // Prototype Demo Controls & Footer
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            children: [
              // Test animation button for prototype (scaled down on narrow columns)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: SleekOutlineButton(
                  height: 38,
                  borderWidth: 1.1,
                  borderColor: const Color(0xFF475569),
                  textColor: const Color(0xFF94A3B8),
                  label: 'TEST PROTOTIPO: TORNA A PC SPENTO',
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  onPressed: () {
                    setState(() => _simulatedOnline = false);
                    _transitionController.reverse();
                  },
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Aggiornamento Realtime • Firebase & Home Assistant',
                  style: TextStyle(
                    color: const Color(0xFF475569).withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Power Control Card with Slender Outline Buttons
  Widget _buildPowerControlCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1015),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F232E), width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    width: 1.1,
                  ),
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: Color(0xFF00E5FF),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alimentazione PC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Presa smart switch.computer_presa_1',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Two slender outline buttons
          Row(
            children: [
              Expanded(
                child: SleekOutlineButton(
                  height: 46,
                  borderWidth: 1.3,
                  borderColor: const Color(0xFFEF4444),
                  textColor: const Color(0xFFEF4444),
                  label: 'SPEGNI PC',
                  icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                  isLoading: _isTurningOffPc,
                  onPressed: _turnOffPcWithConfirmation,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SleekOutlineButton(
                  height: 46,
                  borderWidth: 1.3,
                  borderColor: const Color(0xFF00E5FF),
                  textColor: const Color(0xFF00E5FF),
                  label: 'AGGIORNA',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  isLoading: _isRefreshing,
                  onPressed: () => _fetchData(showLoader: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// App Card with Slender Outline Action Button
  Widget _buildAppCard({
    required AppInfo app,
    required Color accentColor,
    required String iconAsset,
    required String subtitle,
  }) {
    final isOnline = _isEffectiveOnline;
    final isRunning = isOnline && app.isRunning;

    // Button states
    final actionColor = isRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final actionLabel = isRunning
        ? 'ARRESTA ${app.displayName.toUpperCase()}'
        : 'AVVIA ${app.displayName.toUpperCase()}';
    final actionIcon = isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1015),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : const Color(0xFF1F232E),
          width: 1.1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Slender outlined icon avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Image.asset(
                    iconAsset,
                    width: 22,
                    height: 22,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Status Outline Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: !isOnline
                        ? const Color(0xFF475569)
                        : (isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: !isOnline
                            ? const Color(0xFF475569)
                            : (isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOnline ? app.actualState : 'N/D',
                      style: TextStyle(
                        color: !isOnline
                            ? const Color(0xFF94A3B8)
                            : (isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF1A1E29), height: 1),
          const SizedBox(height: 14),

          // Primary Slender Action Button matching "tasti snelli con solo bordo tasti colorato"
          SizedBox(
            width: double.infinity,
            child: SleekOutlineButton(
              height: 44,
              borderWidth: 1.3,
              borderColor: actionColor,
              textColor: actionColor,
              isLoading: app.isMutating,
              label: app.isMutating ? 'ATTENDI PC...' : actionLabel,
              icon: app.isMutating ? null : Icon(actionIcon, size: 20),
              onPressed: isOnline ? () => _toggleAppState(app.key) : null,
            ),
          ),
        ],
      ),
    );
  }
}
