package fyi.genbeya.genbeya_mobile

import android.content.Intent
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.cert.X509Certificate

class MainActivity : FlutterActivity() {
    /** Text shared into the app (Share → Genbeya Mobile), for lib/features/links/shared_text.dart. */
    private var sharedChannel: MethodChannel? = null
    private var pendingShared: String? = null

    private fun sharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            intent.getStringExtra(Intent.EXTRA_TEXT)
        } else {
            null
        }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedText(intent) ?: return
        val channel = sharedChannel
        if (channel != null) channel.invokeMethod("shared", text) else pendingShared = text
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShared = sharedText(intent)
        sharedChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fyi.genbeya/shared").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(pendingShared)
                    pendingShared = null
                } else {
                    result.notImplemented()
                }
            }
        }
        // The system's trusted CA certificates as PEM, for the Git core's OpenSSL
        // (lib/access/native/ca_bundle.dart). Only "system:" entries: like
        // Android's own default for apps, certificates a user added aren't trusted.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fyi.genbeya/certificates")
            .setMethodCallHandler { call, result ->
                if (call.method != "systemCertificates") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val store = KeyStore.getInstance("AndroidCAStore").apply { load(null) }
                        val pems = store.aliases().toList()
                            .filter { it.startsWith("system:") }
                            .mapNotNull { store.getCertificate(it) as? X509Certificate }
                            .map {
                                val body = Base64.encodeToString(it.encoded, Base64.NO_WRAP).chunked(64).joinToString("\n")
                                "-----BEGIN CERTIFICATE-----\n$body\n-----END CERTIFICATE-----"
                            }
                        runOnUiThread { result.success(pems) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("certificates", error.message, null) }
                    }
                }.start()
            }
    }
}
