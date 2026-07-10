package com.cctvspeed.cctvspeedtrack

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Speed Track main activity.
 *
 * Provides the dependency-free WebView file-upload bridge: the site's
 * <input type="file"> triggers the WebView's file selector, which hops
 * over a MethodChannel and returns the picked content:// URIs back to
 * the WebView. No file_picker dependency — that plugin's 10.x line is
 * Kotlin-only and collides with Flutter KGP (see gray_part_pitfalls §1).
 */
class MainActivity : FlutterActivity() {
    // Must match MethodChannel('speedtrack/filepick') in
    // lib/canvas/web_canvas.dart.
    private val channelName = "speedtrack/filepick"
    private val pickRequest = 0x5A11
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "pick") {
                    val multiple = call.argument<Boolean>("multiple") ?: false
                    val mimes = call.argument<List<String>>("mimeTypes") ?: emptyList()
                    openChooser(multiple, mimes, result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun openChooser(
        multiple: Boolean,
        mimes: List<String>,
        result: MethodChannel.Result,
    ) {
        // Drop any abandoned request before starting a new one.
        pendingResult?.success(emptyList<String>())
        pendingResult = result

        val valid = mimes.filter { it.contains("/") }
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
            when {
                valid.isEmpty() -> type = "*/*"
                valid.size == 1 -> type = valid[0]
                else -> {
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, valid.toTypedArray())
                }
            }
        }

        try {
            startActivityForResult(Intent.createChooser(intent, null), pickRequest)
        } catch (e: Exception) {
            pendingResult = null
            result.success(emptyList<String>())
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return

        val result = pendingResult
        pendingResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }

        val uris = ArrayList<String>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(i).uri.toString())
            }
        } else {
            data.data?.let { uris.add(it.toString()) }
        }
        result.success(uris)
    }
}
