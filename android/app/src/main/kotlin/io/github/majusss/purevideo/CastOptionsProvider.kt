package io.github.majusss.purevideo

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        // Default Media Receiver Google (CC1AD845) - oficjalny receiver Google,
        // wspiera HLS z fMP4 (CMAF), DASH, MP4. Zamiana z prywatnego receivera
        // autora "1E357349", ktory nie radzil sobie z fMP4-in-HLS (np.
        // ultrastream.online). Tracimy logo PureVideo na ekranie TV - w zamian
        // dostajemy zgodnosc ze wszystkimi nowoczesnymi formatami strumieni.
        return CastOptions.Builder()
                .setReceiverApplicationId("CC1AD845")
                .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? {
        return null
    }
}