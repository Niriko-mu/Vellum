import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';

import 'app.dart';
import 'reader/tts_audio_handler.dart';
import 'services/diagnostic_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();
  // First frame first: the Android launch theme stays on screen (a white
  // screen) until runApp runs, so nothing may block or throw before it.
  runApp(const VellumApp());
  // Listening (听书) is prepared afterwards. just_audio has no Windows
  // backend, and any plugin failure must simply leave the button hidden
  // instead of breaking startup.
  unawaited(_initListening());
}

/// Catches what the release build would otherwise swallow.
///
/// Without these two hooks a Dart error in a release APK went to logcat and
/// nowhere else: the reader saw a red screen (or a screen that simply stopped)
/// and there was no record on the device to hand back. The log is local only —
/// see [DiagnosticLog].
void _installErrorHandlers() {
  // Framework errors: kept, then still reported to the framework so the debug
  // build keeps its red screen and its console output.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    unawaited(
      DiagnosticLog.record(
        details.exception,
        details.stack,
        context: details.library ?? 'widget',
      ),
    );
  };

  // Errors outside the widget tree — an awaited future nobody caught, a plugin
  // channel failure, an isolate crash. Returning true stops the default
  // "app will be killed" behaviour only in the sense that the zone continues;
  // it is the only hook that sees them at all.
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      DiagnosticLog.record(error, stack, context: 'platform'),
    );
    return false;
  };

  unawaited(DiagnosticLog.init());
}

Future<void> _initListening() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  try {
    ttsHandler = await AudioService.init(
      builder: () => VellumAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.vellum.listening',
        androidNotificationChannelName: 'Vellum 听书',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    // Missing service declaration, plugin channel problems, or a timeout —
    // listening stays unavailable, the reader works as usual.
    ttsHandler = null;
  }
}