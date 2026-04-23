package uz.kadastr.kadastr

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // Opt into the display's highest refresh rate on OEMs (Samsung OneUI etc.)
        // that otherwise clamp Flutter apps to 60Hz.
        val layoutParams = window.attributes
        layoutParams.preferredRefreshRate = 120f
        window.attributes = layoutParams
    }
}
