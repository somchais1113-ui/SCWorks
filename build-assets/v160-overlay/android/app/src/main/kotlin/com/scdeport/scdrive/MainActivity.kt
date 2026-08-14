package com.scdeport.scdrive

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.WindowManager
import com.scdeport.scdrive.speed.VehicleSpeedEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val headUnitChannel = "com.scdeport.scdrive/headunit"
    private val speedEventChannel = "com.scdeport.scdrive/speed"
    private var vehicleSpeedEngine: VehicleSpeedEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val engine = VehicleSpeedEngine(this)
        vehicleSpeedEngine = engine
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, speedEventChannel)
            .setStreamHandler(engine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, headUnitChannel)
            .setMethodCallHandler { call, result ->
                val method = call.method.lowercase()
                when {
                    method == "isgooglemapsconfigured" -> result.success(isGoogleMapsConfigured())
                    method == "startspeedengine" -> {
                        engine.start()
                        result.success(true)
                    }
                    method == "stopspeedengine" -> {
                        engine.stop()
                        result.success(true)
                    }
                    method == "setspeeddebugenabled" -> {
                        engine.setDebugEnabled(call.argument<Boolean>("enabled") == true)
                        result.success(true)
                    }
                    method == "getspeedlogpath" -> result.success(engine.logPath())
                    method == "getelapsedrealtimenanos" -> result.success(SystemClock.elapsedRealtimeNanos())
                    method.contains("home") && (method.contains("is") || method.contains("check")) ->
                        result.success(isDefaultHome())
                    method.contains("home") && (method.contains("request") || method.contains("set") || method.contains("role")) -> {
                        requestHomeRole()
                        result.success(true)
                    }
                    method.contains("home") && method.contains("open") -> {
                        openHomeSettings()
                        result.success(true)
                    }
                    method.contains("screen") && (method.contains("keep") || method.contains("wake")) -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onDestroy() {
        vehicleSpeedEngine?.destroy()
        vehicleSpeedEngine = null
        super.onDestroy()
    }

    private fun isGoogleMapsConfigured(): Boolean {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            val key = appInfo.metaData?.getString("com.google.android.geo.API_KEY")?.trim().orEmpty()
            key.isNotEmpty() && key != "SC_DRIVE_MAPS_DISABLED"
        } catch (_: Exception) {
            false
        }
    }

    private fun isDefaultHome(): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == packageName
    }

    private fun requestHomeRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (roleManager.isRoleAvailable(RoleManager.ROLE_HOME) && !roleManager.isRoleHeld(RoleManager.ROLE_HOME)) {
                startActivityForResult(roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME), 9001)
                return
            }
        }
        openHomeSettings()
    }

    private fun openHomeSettings() {
        try {
            startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
        } catch (_: Exception) {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            startActivity(intent)
        }
    }
}
