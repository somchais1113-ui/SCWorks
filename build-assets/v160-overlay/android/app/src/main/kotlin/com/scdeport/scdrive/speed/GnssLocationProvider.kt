package com.scdeport.scdrive.speed

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Build
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Granularity
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

class GnssLocationProvider(
    context: Context,
    private val looper: Looper,
    private val onLocation: (GnssMeasurement) -> Unit,
    private val onError: (String) -> Unit,
) {
    data class GnssMeasurement(
        val latitude: Double,
        val longitude: Double,
        val speedMps: Double,
        val positionAccuracyM: Double,
        val speedAccuracyMps: Double?,
        val bearingDeg: Double,
        val elapsedRealtimeNanos: Long,
        val usedFallbackSpeed: Boolean,
    )

    private val client: FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(context)
    private var previousLocation: Location? = null

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (location in result.locations) emit(location)
        }
    }

    private val request = LocationRequest.Builder(
        Priority.PRIORITY_HIGH_ACCURACY,
        SpeedEngineConfig.locationIntervalMs,
    )
        .setGranularity(Granularity.GRANULARITY_FINE)
        .setMinUpdateIntervalMillis(SpeedEngineConfig.locationMinIntervalMs)
        .setMinUpdateDistanceMeters(0f)
        .setMaxUpdateAgeMillis(0L)
        .setMaxUpdateDelayMillis(0L)
        .setWaitForAccurateLocation(false)
        .build()

    @SuppressLint("MissingPermission")
    fun start() {
        try {
            client.requestLocationUpdates(request, callback, looper)
        } catch (error: SecurityException) {
            onError("Location permission missing: ${error.message}")
        } catch (error: Exception) {
            onError("Location provider error: ${error.message}")
        }
    }

    fun stop() {
        client.removeLocationUpdates(callback)
    }

    private fun emit(location: Location) {
        val previous = previousLocation
        var usedFallback = false
        val speed = if (location.hasSpeed()) {
            location.speed.toDouble().coerceAtLeast(0.0)
        } else {
            usedFallback = true
            fallbackSpeed(previous, location)
        }
        val speedAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasSpeedAccuracy()) {
            location.speedAccuracyMetersPerSecond.toDouble()
        } else null
        onLocation(
            GnssMeasurement(
                latitude = location.latitude,
                longitude = location.longitude,
                speedMps = speed,
                positionAccuracyM = if (location.hasAccuracy()) location.accuracy.toDouble() else 999.0,
                speedAccuracyMps = speedAccuracy,
                bearingDeg = if (location.hasBearing()) location.bearing.toDouble() else 0.0,
                elapsedRealtimeNanos = location.elapsedRealtimeNanos,
                usedFallbackSpeed = usedFallback,
            ),
        )
        previousLocation = location
    }

    private fun fallbackSpeed(previous: Location?, current: Location): Double {
        if (previous == null) return 0.0
        val dt = (current.elapsedRealtimeNanos - previous.elapsedRealtimeNanos) / 1_000_000_000.0
        if (dt !in 0.1..3.0) return 0.0
        return haversineMeters(previous.latitude, previous.longitude, current.latitude, current.longitude) / dt
    }

    private fun haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earth = 6_371_000.0
        val p1 = Math.toRadians(lat1)
        val p2 = Math.toRadians(lat2)
        val dp = Math.toRadians(lat2 - lat1)
        val dl = Math.toRadians(lon2 - lon1)
        val a = sin(dp / 2).pow(2) + cos(p1) * cos(p2) * sin(dl / 2).pow(2)
        return earth * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
