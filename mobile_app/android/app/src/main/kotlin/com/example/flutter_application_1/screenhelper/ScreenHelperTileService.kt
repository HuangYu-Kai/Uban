package com.example.flutter_application_1.screenhelper

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import com.example.flutter_application_1.R

/**
 * 快速設定磚：顯示／隱藏「手機小幫手」浮鈕。
 * App 無法自己開啟無障礙服務，所以服務沒開時，點磚改為前往系統無障礙設定。
 */
class ScreenHelperTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val svc = ScreenHelperService.instance
        if (svc != null) {
            svc.setBallVisible(!svc.isBallVisible())
            updateTile()
            ScreenHelperState.notifyChanged(this)
            return
        }
        // 服務沒開：鎖屏時先解鎖，再開無障礙設定。
        if (isLocked) unlockAndRun { openAccessibilitySettings() } else openAccessibilitySettings()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val svc = ScreenHelperService.instance
        val (state, sub) = when {
            svc == null -> Tile.STATE_INACTIVE to "未開啟"
            svc.isBallVisible() -> Tile.STATE_ACTIVE to "顯示中"
            else -> Tile.STATE_INACTIVE to "已隱藏"
        }
        tile.state = state
        tile.label = "手機小幫手"
        tile.icon = Icon.createWithResource(this, R.drawable.ic_screen_helper_tile)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = sub
        tile.updateTile()
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pi = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }.onFailure { Log.w("ScreenHelper", "open accessibility settings failed", it) }
    }
}
