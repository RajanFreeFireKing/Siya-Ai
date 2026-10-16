package com.siya.ai.data

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import com.siya.ai.ui.widget.FloatingWindow
import org.json.JSONObject

/**
 * Siya ka map popup: dusre apps ke upar tairta hai, khiskao / chhota-bada karo.
 * Satellite ya normal map (OpenStreetMap). Tiles internet se aate hain.
 */
object MapWindow {
    private var win: FloatingWindow? = null
    private var web: WebView? = null

    private fun html(lat: Double, lng: Double, label: String, satellite: Boolean, zoom: Int): String = """
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css"/>
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"></script>
<style>html,body,#m{height:100%;margin:0;background:#071826}
.sw{position:absolute;z-index:1000;top:8px;left:8px;background:#071826e6;color:#3ee6ff;border:1px solid #22d3ee;border-radius:10px;padding:7px 12px;font:600 13px sans-serif}</style></head>
<body><div id="m"></div><div class="sw" id="sw">${if (satellite) "Map" else "Satellite"}</div>
<script>
var sat=$satellite;
var m=L.map('m',{zoomControl:true}).setView([$lat,$lng],$zoom);
var osm=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'&copy; OpenStreetMap'});
var esri=L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',{maxZoom:19,attribution:'Esri'});
(sat?esri:osm).addTo(m);
L.circleMarker([$lat,$lng],{radius:9,color:'#fff',weight:3,fillColor:'#d946ef',fillOpacity:1}).addTo(m).bindPopup(${JSONObject.quote(label)}).openPopup();
document.getElementById('sw').onclick=function(){sat=!sat;if(sat){m.removeLayer(osm);esri.addTo(m);}else{m.removeLayer(esri);osm.addTo(m);}this.textContent=sat?'Map':'Satellite';};
</script></body></html>"""

    @SuppressLint("SetJavaScriptEnabled")
    fun show(ctx: Context, lat: Double, lng: Double, label: String, satellite: Boolean, zoom: Int = 15): Boolean {
        val app = ctx.applicationContext
        var ok = false
        val latch = java.util.concurrent.CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            try {
                val w = web ?: WebView(app).also {
                    it.settings.javaScriptEnabled = true
                    it.settings.domStorageEnabled = true
                    web = it
                }
                w.loadDataWithBaseURL("https://siya.local/", html(lat, lng, label, satellite, zoom), "text/html", "utf-8", null)
                if (win?.shown != true) {
                    win = FloatingWindow(app, label.ifBlank { "Map" }, w, 0.94f, 0.45f, onClose = { win = null })
                    ok = win!!.show()
                    if (!ok) win = null
                } else { win?.setTitle(label.ifBlank { "Map" }); ok = true }
            } catch (_: Exception) {}
            latch.countDown()
        }
        latch.await(4, java.util.concurrent.TimeUnit.SECONDS)
        return ok
    }

    fun resize(mode: String) { Handler(Looper.getMainLooper()).post { win?.resize(mode) } }
    fun close() { Handler(Looper.getMainLooper()).post { win?.close(); web?.loadUrl("about:blank") } }
    fun isShowing() = win?.shown == true
}
