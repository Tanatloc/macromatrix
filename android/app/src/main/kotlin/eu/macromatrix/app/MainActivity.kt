package eu.macromatrix.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingVoice: MethodChannel.Result? = null

    /** Reserve voor spraak: het gewone spraakvenster van Android (Google) als de ingebouwde herkenning faalt. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "macromatrix/voice").setMethodCallHandler { call, result ->
            if (call.method == "available") {
                val probe = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                return@setMethodCallHandler result.success(probe.resolveActivity(packageManager) != null)
            }
            if (call.method != "recognize") return@setMethodCallHandler result.notImplemented()
            pendingVoice?.success(null)
            pendingVoice = result
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                call.argument<String>("language")?.let { putExtra(RecognizerIntent.EXTRA_LANGUAGE, it) }
                call.argument<String>("prompt")?.let { putExtra(RecognizerIntent.EXTRA_PROMPT, it) }
            }
            if (intent.resolveActivity(packageManager) == null) {
                pendingVoice = null
                return@setMethodCallHandler result.error("unavailable", "No speech recognition app", null)
            }
            try {
                @Suppress("DEPRECATION")
                startActivityForResult(intent, VOICE_REQUEST)
            } catch (e: ActivityNotFoundException) {
                pendingVoice = null
                result.error("unavailable", "No speech recognition app", null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VOICE_REQUEST) return
        val text = if (resultCode == Activity.RESULT_OK) data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null
        pendingVoice?.success(text)
        pendingVoice = null
    }

    companion object {
        private const val VOICE_REQUEST = 4711
    }
}
