package com.siya.ai.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Phone ki asli location + user ki "custom" (map se chuni hui) location. */
object LocationHelper {

    fun hasPermission(ctx: Context) =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    fun device(ctx: Context): Location? {
        if (!hasPermission(ctx)) return null
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        var best: Location? = null
        for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)) {
            try {
                val l = lm.getLastKnownLocation(p) ?: continue
                if (best == null || l.time > best!!.time) best = l
            } catch (_: Exception) {}
        }
        val fresh = best != null && System.currentTimeMillis() - best!!.time < 5 * 60_000
        if (!fresh && Build.VERSION.SDK_INT >= 30) {
            val provider = when {
                lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
                else -> null
            }
            if (provider != null) {
                val latch = CountDownLatch(1)
                var got: Location? = null
                val cs = CancellationSignal()
                try {
                    lm.getCurrentLocation(provider, cs, ctx.mainExecutor) { l -> got = l; latch.countDown() }
                    if (!latch.await(7, TimeUnit.SECONDS)) cs.cancel()
                } catch (_: Exception) {}
                if (got != null) best = got
            }
        }
        return best
    }

    fun placeName(ctx: Context, lat: Double, lng: Double): String = try {
        @Suppress("DEPRECATION")
        val a = Geocoder(ctx, Locale.getDefault()).getFromLocation(lat, lng, 1)?.firstOrNull()
        a?.getAddressLine(0) ?: "%.5f, %.5f".format(lat, lng)
    } catch (_: Exception) { "%.5f, %.5f".format(lat, lng) }

    /** Naam se jagah dhundo (Geocoder; phone mein Google services ho to). */
    fun search(ctx: Context, q: String): Map<String, Any?>? = try {
        @Suppress("DEPRECATION")
        val a = Geocoder(ctx, Locale.getDefault()).getFromLocationName(q, 1)?.firstOrNull()
        a?.let { mapOf("lat" to it.latitude, "lng" to it.longitude, "name" to (it.getAddressLine(0) ?: q)) }
    } catch (_: Exception) { null }

    /** Siya ke liye: jagah ka naam -> prefs mein custom location set. */
    fun setCustom(ctx: Context, query: String): String {
        val r = search(ctx, query) ?: return "NOT_FOUND: '$query' jagah nahi mili"
        val lat = (r["lat"] as Double); val lng = (r["lng"] as Double); val name = r["name"] as String
        ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).edit()
            .putString("loc_mode", "custom").putFloat("loc_lat", lat.toFloat()).putFloat("loc_lng", lng.toFloat()).putString("loc_name", name).apply()
        return "OK: location set ho gayi: $name (lat $lat, lng $lng)"
    }

    fun useDevice(ctx: Context): String {
        ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE).edit().putString("loc_mode", "device").apply()
        return "OK: ab phone ki asli location use hogi"
    }

    /** Tool ke liye text: custom location chuni ho to wahi, warna GPS. */
    fun describe(ctx: Context): String {
        val p = ctx.getSharedPreferences("siya_prefs", Context.MODE_PRIVATE)
        if (p.getString("loc_mode", "device") == "custom" && p.contains("loc_lat")) {
            val lat = p.getFloat("loc_lat", 0f).toDouble(); val lng = p.getFloat("loc_lng", 0f).toDouble()
            val name = p.getString("loc_name", "").orEmpty().ifBlank { placeName(ctx, lat, lng) }
            return "User ne map par yeh location set ki hai: $name (lat $lat, lng $lng)"
        }
        val l = device(ctx) ?: return if (hasPermission(ctx)) "ERROR: location abhi nahi mili (GPS on karo)" else "ERROR: Location permission nahi hai (Settings > Permissions)"
        return "Phone ki abhi ki location: ${placeName(ctx, l.latitude, l.longitude)} (lat ${l.latitude}, lng ${l.longitude})"
    }
}
