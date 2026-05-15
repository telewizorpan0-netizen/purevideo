package io.github.majusss.purevideo

import android.content.Context
import android.util.Log
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

class CastOptionsProvider : OptionsProvider {
    companion object {
        private const val TAG = "CastOptionsProvider"

        // Default Media Receiver Google - oficjalny receiver, wspiera MP4 i
        // podstawowe HLS/DASH. NIE radzi sobie dobrze z fMP4-in-HLS (CMAF) -
        // dla takich strumieni user musi wpisac wlasny custom receiver ID.
        private const val DEFAULT_RECEIVER_ID = "CC1AD845"

        // Klucz musi byc identyczny z [SettingsService._castReceiverAppIdKey].
        // Plugin shared_preferences zapisuje stringi z prefiksem "flutter.".
        private const val PREF_KEY = "flutter.castReceiverAppId"
        private const val PREF_FILE = "FlutterSharedPreferences"
    }

    override fun getCastOptions(context: Context): CastOptions {
        val appId = readReceiverAppId(context)
        Log.i(TAG, "Cast receiver applicationId: $appId")
        return CastOptions.Builder()
                .setReceiverApplicationId(appId)
                .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? {
        return null
    }

    private fun readReceiverAppId(context: Context): String {
        return try {
            val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
            val raw = prefs.getString(PREF_KEY, null)?.trim().orEmpty()
            if (raw.isEmpty()) DEFAULT_RECEIVER_ID else raw.uppercase()
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to read receiverAppId from SharedPreferences", t)
            DEFAULT_RECEIVER_ID
        }
    }
}
