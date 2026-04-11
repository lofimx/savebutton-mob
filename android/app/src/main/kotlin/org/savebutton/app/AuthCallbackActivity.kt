package org.savebutton.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.linusu.flutter_web_auth_2.FlutterWebAuth2Plugin

/**
 * Custom callback activity for OAuth redirects that closes the Chrome Custom Tab.
 *
 * The default CallbackActivity from flutter_web_auth_2 calls finishAndRemoveTask()
 * on itself but cannot close the Chrome Custom Tab since it runs in a separate task.
 *
 * This activity delivers the callback to the Flutter plugin, then explicitly launches
 * MainActivity to bring the app to the foreground. Using FLAG_ACTIVITY_NEW_TASK
 * ensures the main app task is brought forward, and finishAndRemoveTask() removes
 * this callback activity's task (which also contains the Custom Tab).
 */
class AuthCallbackActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent?.data
        val scheme = url?.scheme

        if (scheme != null) {
            FlutterWebAuth2Plugin.callbacks.remove(scheme)?.success(url.toString())
        }

        // Bring MainActivity's task to the foreground
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(mainIntent)

        // Remove this activity's task (and the Custom Tab within it) from recents
        finishAndRemoveTask()
    }
}
