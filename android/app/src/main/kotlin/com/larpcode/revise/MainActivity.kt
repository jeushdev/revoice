package com.larpcode.revise

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Keep speech initialization unavailable until devJ's real factory is ready.
        flutterEngine.plugins.add(ReviseEnginePlugin())
    }
}
