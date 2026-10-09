import 'package:flutter/services.dart';

import 'caption_engine.dart';
import 'engine_events.dart';

class PlatformCaptionEngine implements CaptionEngine {
  static const _methods = MethodChannel('revise/engine');
  static const _captions = EventChannel('revise/captions');

  late final Stream<EngineEvent> _events = _captions
      .receiveBroadcastStream()
      .map(EngineEvent.fromMap)
      .where((e) => e != null)
      .cast<EngineEvent>();

  @override
  Stream<EngineEvent> get events => _events;

  @override
  Future<InitResult> init() async {
    final r = await _call<Map<Object?, Object?>>('init');
    return InitResult(
      sttReady: r?['sttReady'] == true,
      llmReady: r?['llmReady'] == true,
    );
  }

  /// Names to bias the speech model towards for the NEXT start (set by SessionController from the
  /// names typed before recording). Not part of [CaptionEngine] so other engines are unaffected.
  List<String> keyterms = const [];

  @override
  Future<void> start({String language = 'en'}) =>
      _call<bool>('start', {'language': language, 'keyterms': keyterms});

  @override
  Future<void> pause() => _call<bool>('pause');

  @override
  Future<void> resume() => _call<bool>('resume');

  @override
  Future<void> stop() => _call<bool>('stop');

  @override
  Future<String> cleanLine({
    required String text,
    required String prompt,
    int maxTokens = 512,
  }) async {
    final r = await _call<Map<Object?, Object?>>('cleanLine', {
      'text': text,
      'prompt': prompt,
      'maxTokens': maxTokens,
    });
    return r?['text'] as String? ?? text;
  }

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    bool json = true,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  }) async {
    final grammar = jsonGrammar ?? (json ? true : null);
    final r = await _call<Map<Object?, Object?>>('generate', {
      'prompt': prompt,
      'maxTokens': maxTokens,
      if (system != null) 'system': system,
      if (grammar != null) 'jsonGrammar': grammar,
      if (requestId != null) 'requestId': requestId,
    });
    return r?['text'] as String? ?? '';
  }

  @override
  Future<void> dispose() async {}

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw EngineException(EngineErrorCode.fromWire(e.code), e.message);
    } on MissingPluginException {
      throw const EngineException(
        EngineErrorCode.modelMissing,
        'Native engine not available on this platform. Use Demo mode.',
      );
    }
  }
}
