package online.divinenet.macromatrix

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Health Connect: "Why does this app need access?" (permission screen, Android 13 and lower) and the privacy link in
 * the Health Connect permissions (Android 14+). Opens the privacy policy, which explains which health data is read and
 * why, and closes again without starting the app.
 */
class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            // No browser: nothing to show
        }
        finish()
    }

    companion object {
        const val PRIVACY_URL = "https://app.divinenet.online/privacy/#health-connect"
    }
}
