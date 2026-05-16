package com.nusha.messenger

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE: enables in PRODUCTION — blocks screenshots AND App Switcher preview
        // For demo builds: FLAG_SECURE is OFF so we can take ADB screenshots
        // In release build (--release), enable this:
        // window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }
}
