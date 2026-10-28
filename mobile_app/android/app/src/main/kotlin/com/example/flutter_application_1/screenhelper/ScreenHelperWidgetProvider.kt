package com.example.flutter_application_1.screenhelper

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.widget.RemoteViews
import com.example.flutter_application_1.R

/**
 * 桌面 1×1 小工具：顯示／隱藏「手機小幫手」浮鈕，與快速設定磚共用同一個開關。
 * 服務沒開時，點小工具改為前往系統無障礙設定。
 */
class ScreenHelperWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { manager.updateAppWidget(it, buildViews(context)) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_TOGGLE) return
        val svc = ScreenHelperService.instance
        // setBallVisible 會觸發 notifyChanged 刷新；服務不在時狀態可能過期，直接重畫。
        if (svc != null) svc.setBallVisible(!svc.isBallVisible()) else updateAll(context)
    }

    companion object {
        const val ACTION_TOGGLE = "com.example.flutter_application_1.screenhelper.TOGGLE"

        fun updateAll(ctx: Context) {
            val manager = AppWidgetManager.getInstance(ctx)
            val ids = manager.getAppWidgetIds(ComponentName(ctx, ScreenHelperWidgetProvider::class.java))
            if (ids.isEmpty()) return
            ids.forEach { manager.updateAppWidget(it, buildViews(ctx)) }
        }

        private fun buildViews(ctx: Context): RemoteViews {
            val svc = ScreenHelperService.instance
            val views = RemoteViews(ctx.packageName, R.layout.screen_helper_widget)
            val on = svc != null && svc.isBallVisible()
            val status = when {
                svc == null -> "未開啟"
                on -> "開"
                else -> "關"
            }
            views.setInt(
                R.id.widget_circle, "setBackgroundResource",
                if (on) R.drawable.screen_helper_widget_bg_on else R.drawable.screen_helper_widget_bg_off,
            )
            views.setTextViewText(R.id.widget_label, "小幫手")
            views.setTextViewText(R.id.widget_status, status)

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pi = if (svc != null) {
                PendingIntent.getBroadcast(
                    ctx, 0,
                    Intent(ctx, ScreenHelperWidgetProvider::class.java).setAction(ACTION_TOGGLE),
                    flags,
                )
            } else {
                // Activity PendingIntent 可避開背景啟動 Activity 的限制。
                PendingIntent.getActivity(
                    ctx, 1,
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    flags,
                )
            }
            views.setOnClickPendingIntent(R.id.widget_root, pi)
            return views
        }
    }
}
