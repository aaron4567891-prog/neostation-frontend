import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/systems_update_service.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/systems_update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    SfxService().setEnabled(false);

    // Stub the gamepads plugin so GamepadNavigation.initialize() finds no
    // devices instead of relying on a real platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/gamepads'),
          (call) async => <dynamic>[],
        );

    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  const updateInfo = SystemsUpdateInfo(
    currentVersion: '0.3.9',
    remoteVersion: '0.3.11',
  );

  // Matches ScreenUtilInit in main.dart. At the RG DS's 640x480 panel the
  // scale factor is therefore exactly 1.0, which is the tightest case the
  // dialog ever sees — larger screens scale it up proportionally.
  const appDesignSize = Size(640, 480);

  /// Pumps the dialog at [size] with an injected [runner].
  ///
  /// The RG DS is the smallest panel the app targets, and the download state is
  /// the tallest the dialog ever gets, so 640x480 is the case worth pinning.
  Future<void> pumpDialog(
    WidgetTester tester, {
    required SystemsUpdateRunner runner,
    Size size = const Size(640, 480),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: ScreenUtilInit(
          designSize: appDesignSize,
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Scaffold(
              body: SystemsUpdateDialog(updateInfo: updateInfo, runner: runner),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A runner that never completes, parking the dialog in its download state.
  SystemsUpdateRunner pendingRunner({
    void Function(bool Function()? shouldCancel)? capture,
    void Function(void Function(double, String)? onProgress)? captureProgress,
  }) {
    return ({knownUpdate, onProgress, shouldCancel}) {
      capture?.call(shouldCancel);
      captureProgress?.call(onProgress);
      return Completer<SystemsUpdateResult?>().future;
    };
  }

  testWidgets('idle dialog fits a 640x480 panel', (tester) async {
    await pumpDialog(tester, runner: pendingRunner());

    expect(find.text('UPDATE NOW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download state fits a 640x480 panel', (tester) async {
    await pumpDialog(tester, runner: pendingRunner());

    await tester.tap(find.text('UPDATE NOW'));
    await tester.pump();

    // The download state adds a progress bar and a cancel row over the idle
    // layout; an overflow here would surface as a RenderFlex exception.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel control is offered while downloading', (tester) async {
    await pumpDialog(tester, runner: pendingRunner());

    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.text('UPDATE NOW'));
    await tester.pump();

    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('tapping cancel flips the shouldCancel signal', (tester) async {
    bool Function()? captured;
    await pumpDialog(
      tester,
      runner: pendingRunner(capture: (s) => captured = s),
    );

    await tester.tap(find.text('UPDATE NOW'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!(), isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(captured!(), isTrue);
  });

  testWidgets('progress updates drive the status line', (tester) async {
    void Function(double, String)? progress;
    await pumpDialog(
      tester,
      runner: pendingRunner(captureProgress: (p) => progress = p),
    );

    await tester.tap(find.text('UPDATE NOW'));
    await tester.pump();

    progress!(0.5, 'Downloading systems (60/121)...');
    await tester.pump();

    expect(find.text('Downloading systems (60/121)...'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('cancelling freezes the status line at cancelling', (
    tester,
  ) async {
    void Function(double, String)? progress;
    await pumpDialog(
      tester,
      runner: pendingRunner(captureProgress: (p) => progress = p),
    );

    await tester.tap(find.text('UPDATE NOW'));
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    // Downloads already in flight keep reporting; they must not overwrite the
    // cancelling message.
    progress!(0.9, 'Downloading systems (110/121)...');
    await tester.pump();

    expect(find.text('Cancelling...'), findsOneWidget);
    expect(find.text('Downloading systems (110/121)...'), findsNothing);
  });

  Future<BuildContext> pumpControllerHost(
    WidgetTester tester,
    VoidCallback onNavigate,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: appDesignSize,
        builder: (context, child) => MaterialApp(
          localizationsDelegates:
              FlutterLocalization.instance.localizationsDelegates,
          supportedLocales: FlutterLocalization.instance.supportedLocales,
          home: Builder(
            builder: (context) {
              hostContext = context;
              return _ControllerHost(onNavigate: onNavigate);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return hostContext;
  }

  Future<void> settleInput(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );

  for (final dismissal in ['B', 'touch', 'download cancellation']) {
    testWidgets('controller works after updater closes through $dismissal', (
      tester,
    ) async {
      var moves = 0;
      final context = await pumpControllerHost(tester, () => moves++);
      final depth = GamepadNavigationManager.stackDepth;
      final download = Completer<SystemsUpdateResult?>();
      final closed = showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SystemsUpdateDialog(
          updateInfo: updateInfo,
          runner: ({knownUpdate, onProgress, shouldCancel}) => download.future,
        ),
      );
      await tester.pumpAndSettle();
      await settleInput(tester);

      // The modal keeps navigation off the underlying systems view.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(moves, 0);
      await settleInput(tester);

      if (dismissal == 'touch') {
        await tester.tap(find.text('LATER'));
      } else {
        if (dismissal == 'download cancellation') {
          await tester.tap(find.text('UPDATE NOW'));
          await tester.pump();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        if (dismissal == 'download cancellation') {
          await tester.pump();
          expect(find.text('Cancelling...'), findsOneWidget);
          download.complete(null);
        }
      }
      await tester.pumpAndSettle();
      expect(find.byType(SystemsUpdateDialog), findsNothing);
      expect(await closed, isFalse);
      expect(GamepadNavigationManager.stackDepth, depth);

      // No touch on a top tab is needed to restore the controller.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(moves, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _ControllerHost extends StatefulWidget {
  const _ControllerHost({required this.onNavigate});

  final VoidCallback onNavigate;

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost> {
  late final GamepadNavigation _nav;

  @override
  void initState() {
    super.initState();
    _nav = GamepadNavigation(onNavigateRight: widget.onNavigate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nav.initialize();
      GamepadNavigationManager.pushLayer(
        'systems_update_test_host',
        onActivate: () {
          // The real systems carousel also declines focus on a covered route.
          if (ModalRoute.of(context)?.isCurrent == true) _nav.activate();
        },
        onDeactivate: _nav.deactivate,
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('systems_update_test_host');
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
