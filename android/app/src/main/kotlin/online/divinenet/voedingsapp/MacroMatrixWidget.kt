package online.divinenet.voedingsapp

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Widget op het startscherm: kcal over vandaag, je reeks en een knop om snel te loggen. De app vult de waarden in. */
class MacroMatrixWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.macromatrix_widget).apply {
                setTextViewText(R.id.widget_kcal, widgetData.getString("kcal", "–"))
                setTextViewText(R.id.widget_kcal_label, widgetData.getString("kcal_label", "kcal left"))
                setTextViewText(R.id.widget_streak, widgetData.getString("streak", "0"))
                setTextViewText(R.id.widget_streak_label, widgetData.getString("streak_label", "days"))
                setTextViewText(R.id.widget_log, "+  " + widgetData.getString("log_label", "Log"))
                val hint = widgetData.getString("hint", "") ?: ""
                setTextViewText(R.id.widget_hint, hint)
                setViewVisibility(R.id.widget_hint, if (hint.isEmpty()) View.GONE else View.VISIBLE)
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("macromatrix://today")))
                setOnClickPendingIntent(R.id.widget_log, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("macromatrix://quicklog")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
