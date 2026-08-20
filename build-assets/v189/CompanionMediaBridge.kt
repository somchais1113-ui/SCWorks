package com.scdeport.scdrive.media

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Keeps Radio Garden and Spotify launches inside their installed Android apps.
 * SC Drive deliberately does not fall back to a browser: if the companion app
 * is unavailable the Flutter UI receives false and can show a clear status.
 *
 * The bridge also accepts ACTION_SEND text shares so a Radio Garden station or
 * Spotify item can be saved once inside SC Drive and reused as a local favorite.
 */
class CompanionMediaBridge(private val activity: Activity) :
    EventChannel.StreamHandler,
    MethodChannel.MethodCallHandler {

    companion object {
        private const val RADIO_GARDEN_PACKAGE = "com.jonathanpuckey.radiogarden"
        private const val SPOTIFY_PACKAGE = "com.spotify.music"
    }

    private var sink: EventChannel.EventSink? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        pendingShare?.let { events?.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method.lowercase(Locale.US)) {
            "openradiogarden" -> {
                val uri = call.argument<String>("uri")?.trim().orEmpty()
                result.success(openRadioGarden(uri))
            }
            "openspotify" -> {
                val uri = call.argument<String>("uri")?.trim().orEmpty()
                result.success(openSpotify(uri))
            }
            "isinstalled" -> {
                val target = call.argument<String>("target")?.trim()?.lowercase(Locale.US)
                val pkg = when (target) {
                    "radio_garden", "radiogarden" -> RADIO_GARDEN_PACKAGE
                    "spotify" -> SPOTIFY_PACKAGE
                    else -> null
                }
                result.success(pkg != null && isInstalled(pkg))
            }
            "getpendingshare" -> result.success(pendingShare)
            "clearpendingshare" -> {
                pendingShare = null
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    fun handleIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        if (intent.type?.startsWith("text/", ignoreCase = true) != true) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        if (text.isEmpty()) return
        val parsed = parseShare(text) ?: return
        pendingShare = parsed
        sink?.success(parsed)
    }

    fun destroy() {
        sink = null
        pendingShare = null
    }

    private fun openRadioGarden(raw: String): Boolean {
        if (!isInstalled(RADIO_GARDEN_PACKAGE)) return false
        val target = raw.ifBlank { "https://radio.garden/" }
        val uri = Uri.parse(target)
        val direct = Intent(Intent.ACTION_VIEW, uri)
            .setPackage(RADIO_GARDEN_PACKAGE)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (canResolve(direct)) return start(direct)
        return launchPackage(RADIO_GARDEN_PACKAGE)
    }

    private fun openSpotify(raw: String): Boolean {
        if (!isInstalled(SPOTIFY_PACKAGE)) return false
        val canonical = spotifyUri(raw)
        if (canonical == null || canonical == "spotify:") {
            return launchPackage(SPOTIFY_PACKAGE)
        }
        val direct = Intent(Intent.ACTION_VIEW, Uri.parse(canonical))
            .setPackage(SPOTIFY_PACKAGE)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (canResolve(direct)) return start(direct)
        return launchPackage(SPOTIFY_PACKAGE)
    }

    private fun launchPackage(packageName: String): Boolean {
        val intent = try {
            activity.packageManager.getLaunchIntentForPackage(packageName)
        } catch (_: Exception) {
            null
        } ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return start(intent)
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    private fun canResolve(intent: Intent): Boolean = try {
        intent.resolveActivity(activity.packageManager) != null
    } catch (_: Exception) {
        false
    }

    private fun isInstalled(packageName: String): Boolean = try {
        activity.packageManager.getPackageInfo(packageName, PackageManager.GET_ACTIVITIES)
        true
    } catch (_: Exception) {
        false
    }

    private fun parseShare(text: String): Map<String, Any?>? {
        val url = Regex("(https?://[^\\s]+|spotify:[^\\s]+)", RegexOption.IGNORE_CASE)
            .find(text)?.value?.trimEnd('.', ',', ';', ')', ']', '}') ?: return null
        val lower = url.lowercase(Locale.US)
        val source = when {
            lower.contains("radio.garden/") -> "radio_garden"
            lower.startsWith("spotify:") || lower.contains("open.spotify.com/") -> "spotify"
            else -> return null
        }
        val label = text.replace(url, "")
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(96)
        return mapOf(
            "source" to source,
            "url" to url,
            "label" to label,
            "text" to text.take(512),
        )
    }

    private fun spotifyUri(raw: String): String? {
        val value = raw.trim()
        if (value.isBlank() || value == "spotify:") return "spotify:"
        if (value.startsWith("spotify:", ignoreCase = true)) return value
        val uri = try { Uri.parse(value) } catch (_: Exception) { return null }
        if (!uri.host.orEmpty().equals("open.spotify.com", ignoreCase = true)) return value
        val parts = uri.pathSegments.filter { it.isNotBlank() }
        if (parts.size < 2) return "spotify:"
        val type = parts[0].lowercase(Locale.US)
        if (type !in setOf("track", "playlist", "album", "artist", "show", "episode")) {
            return "spotify:"
        }
        return "spotify:$type:${parts[1]}"
    }
}
