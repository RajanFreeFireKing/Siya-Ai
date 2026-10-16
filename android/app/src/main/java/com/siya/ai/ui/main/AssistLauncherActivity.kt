package com.siya.ai.ui.main

import android.app.Activity
import android.os.Bundle
import com.siya.ai.service.SiyaService

/**
 * Default assistant (power button / gesture) se aane par app nahi khulta.
 * User ka home screen / jo app khula hai wahi rehta hai, Siya overlay mein sunti aur bolti hai.
 */
class AssistLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (SiyaService.instance?.isSessionActive() == true) SiyaService.send(this, SiyaService.ACTION_STOP, "assist")
        else if (!SiyaService.send(this, SiyaService.ACTION_START, "assist")) {
            // Mic permission abhi nahi mili: pehli baar app khol kar permission maango
            startActivity(android.content.Intent(this, MainActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        finish()
        overridePendingTransition(0, 0)
    }
}
