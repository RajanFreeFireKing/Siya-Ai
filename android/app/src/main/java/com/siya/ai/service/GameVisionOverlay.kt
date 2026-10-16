package com.siya.ai.service

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import com.siya.ai.core.GameTouchMapping

/** Transparent calibration overlay; taps on actual game-button centers are saved as percentages. */
object GameVisionOverlay {
    private var overlay: CalibrationView? = null
    private var wm: WindowManager? = null
    fun show(context: Context): String {
        if (!Settings.canDrawOverlays(context)) return "ERROR: Display over other apps permission ON karo."
        if (overlay != null) return "OK: Game mapping calibration pehle se open hai."
        val app=context.applicationContext
        val manager=app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view=CalibrationView(app) { message -> close(message) }
        @Suppress("DEPRECATION")
        val type=if(Build.VERSION.SDK_INT>=26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val lp=WindowManager.LayoutParams(WindowManager.LayoutParams.MATCH_PARENT,WindowManager.LayoutParams.MATCH_PARENT,type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,PixelFormat.TRANSLUCENT)
            .apply { gravity=Gravity.TOP or Gravity.START }
        return try { manager.addView(view,lp); overlay=view; wm=manager
            "OK: Calibration shuru. FIRE, JUMP, CROUCH, GLOO WALL, SPRINT, JOYSTICK ke centers tap karo."
        } catch(e:Exception) { overlay=null; wm=null; "ERROR: Calibration overlay nahi khula: "+(e.message ?: "unknown") }
    }
    private fun close(message:String) {
        val v=overlay ?: return
        try { wm?.removeView(v) } catch(_:Exception) {}
        overlay=null; wm=null
        Toast.makeText(v.context,message,Toast.LENGTH_LONG).show()
    }
    private class CalibrationView(context:Context,private val onClose:(String)->Unit):View(context) {
        private val d=resources.displayMetrics.density
        private val p=Paint(Paint.ANTI_ALIAS_FLAG)
        private val bar=RectF()
        private val buttons=GameTouchMapping.Button.values()
        private var index=0
        private var note=""
        override fun onDraw(c:Canvas) {
            c.drawColor(0x33000000)
            val bh=104f*d; bar.set(0f,0f,width.toFloat(),bh)
            p.color=0xEE07111F.toInt(); c.drawRoundRect(bar,14f*d,14f*d,p)
            p.color=0xFF8B5CF6.toInt(); c.drawRect(0f,bh-3f*d,width.toFloat(),bh,p)
            p.color=android.graphics.Color.WHITE; p.textSize=16f*d; p.isFakeBoldText=true
            c.drawText(if(index<buttons.size) "Tap "+buttons[index].label+" button center" else "All six buttons mapped",16f*d,27f*d,p)
            p.isFakeBoldText=false; p.textSize=12f*d
            c.drawText(if(index<buttons.size) (index+1).toString()+"/"+buttons.size+" • exact center tap karo" else "SAVE dabao ya overlay band karo",16f*d,48f*d,p)
            if(note.isNotBlank()) c.drawText(note,16f*d,68f*d,p)
            val cancel=RectF(12f*d,76f*d,86f*d,98f*d); val undo=RectF(96f*d,76f*d,170f*d,98f*d); val save=RectF(width-90f*d,76f*d,width-12f*d,98f*d)
            p.color=0xFF263449.toInt(); c.drawRoundRect(cancel,8f*d,8f*d,p); c.drawRoundRect(undo,8f*d,8f*d,p)
            p.color=0xFF6D4AFF.toInt(); c.drawRoundRect(save,8f*d,8f*d,p)
            p.color=android.graphics.Color.WHITE; p.textSize=10f*d
            c.drawText("CANCEL",22f*d,91f*d,p); c.drawText("UNDO",116f*d,91f*d,p); c.drawText("SAVE",width-70f*d,91f*d,p)
        }
        override fun onTouchEvent(e:MotionEvent):Boolean {
            if(e.actionMasked!=MotionEvent.ACTION_UP) return true
            if(e.y<104f*d) {
                when { e.x<90f*d -> onClose("Game mapping calibration cancel ki."); e.x>width-94f*d -> onClose("Game touch mapping save ho gayi."); e.x<180f*d -> { index=(index-1).coerceAtLeast(0); invalidate() } }
                return true
            }
            if(index>=buttons.size) return true
            val point=GameTouchMapping.set(context,buttons[index],e.x*100f/width.coerceAtLeast(1),e.y*100f/height.coerceAtLeast(1))
            note=buttons[index].label+": "+"%.1f".format(java.util.Locale.ROOT,point.xPercent)+"%, "+"%.1f".format(java.util.Locale.ROOT,point.yPercent)+"%"
            index++; if(index>=buttons.size) note="All six mapped. Tap SAVE to finish."
            invalidate(); return true
        }
    }
}
