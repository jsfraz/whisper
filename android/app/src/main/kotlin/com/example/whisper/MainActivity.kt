package cz.josefraz.whisper

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

// https://medium.com/@sharansukesh2000/protecting-your-flutter-app-implementing-screenshot-prevention-3c06d028e682
class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // below line prevents the user from taking screenshot or record the screen
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }
}