package com.iq3run.session_timer

import android.content.Intent
import android.widget.RemoteViewsService

class ScheduleWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory {
        return ScheduleRemoteViewsFactory(applicationContext)
    }
}
