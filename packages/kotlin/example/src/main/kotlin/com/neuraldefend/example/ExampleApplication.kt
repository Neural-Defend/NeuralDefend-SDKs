package com.neuraldefend.example

import android.app.Application
import com.neuraldefend.kotlin.NeuroVerifyClient
import okhttp3.OkHttpClient

/** Which NeuroVerify deployment the demo calls. */
enum class Environment { STAGING, PRODUCTION }

/** Creates a client for the key the user typed. Tests replace it to target a local server. */
fun interface ClientFactory {
    fun create(apiKey: String, environment: Environment): NeuroVerifyClient
}

class ExampleApplication : Application() {
    /** One connection pool for the whole app; every SDK client derives from it. */
    private val http: OkHttpClient by lazy { OkHttpClient() }

    @Volatile
    var clientFactory: ClientFactory = ClientFactory { apiKey, environment ->
        NeuroVerifyClient.builder()
            .apiKey(apiKey)
            .apply { if (environment == Environment.STAGING) staging() }
            .okHttpClient(http)
            .build()
    }
}
