package com.example.flutter_application_1.screenhelper

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import android.util.Log

/** 小幫手狀態變動時，同步刷新快速設定磚與桌面小工具。 */
object ScreenHelperState {
    fun notifyChanged(ctx: Context) {
        val app = ctx.applicationContext
        runCatching {
            TileService.requestListeningState(
                app, ComponentName(app, ScreenHelperTileService::class.java),
            )
        }.onFailure { Log.w("ScreenHelper", "refresh tile failed", it) }
        runCatching { ScreenHelperWidgetProvider.updateAll(app) }
            .onFailure { Log.w("ScreenHelper", "refresh widget failed", it) }
    }
}
