package com.zilv.clock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AlarmScheduler.restorePersistedAlarms(context)
        TaskOverviewWidgetProvider.refreshAll(context)
    }
}
