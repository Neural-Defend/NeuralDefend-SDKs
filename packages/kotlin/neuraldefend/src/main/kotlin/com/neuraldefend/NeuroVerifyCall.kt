package com.neuraldefend

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.cancellation.CancellationException

/** Completion callback for [NeuroVerifyCall.enqueue]. Invoked on a background thread. */
public interface NeuroVerifyCallback<T> {
    public fun onResult(call: NeuroVerifyCall<T>, result: T)

    public fun onFailure(call: NeuroVerifyCall<T>, error: NeuroVerifyError)
}

/**
 * A single detection request for Java and callback-based code, modeled on OkHttp's `Call`.
 * Run it once with [execute] or [enqueue]; [cancel] stops it at any point and surfaces an
 * [AbortError]. Kotlin coroutine code can call the suspend functions on [NeuroVerifyClient]
 * directly instead.
 */
public class NeuroVerifyCall<T> internal constructor(
    private val scope: CoroutineScope,
    private val block: suspend () -> T,
) {
    private val started = AtomicBoolean(false)
    private val canceled = AtomicBoolean(false)
    private val job = AtomicReference<Job?>(null)

    /** `true` after [cancel] was called. */
    public val isCanceled: Boolean get() = canceled.get()

    /**
     * Runs the request on the calling thread and returns the result. Never call this on the
     * Android main thread.
     *
     * @throws NeuroVerifyError for operational failures, including [AbortError] after [cancel].
     */
    @Throws(NeuroVerifyError::class)
    public fun execute(): T {
        markStarted()
        if (canceled.get()) throw AbortError()
        return try {
            runBlocking {
                attach(coroutineContext[Job])
                block()
            }
        } catch (error: CancellationException) {
            if (canceled.get()) throw AbortError()
            throw error
        }
    }

    /** Runs the request in the background and reports the outcome to [callback] exactly once. */
    public fun enqueue(callback: NeuroVerifyCallback<T>) {
        markStarted()
        if (canceled.get()) {
            callback.onFailure(this, AbortError())
            return
        }
        val launched = scope.launch {
            val outcome = try {
                Result.success(block())
            } catch (error: CancellationException) {
                if (canceled.get()) Result.failure(AbortError()) else throw error
            } catch (error: NeuroVerifyError) {
                Result.failure(error)
            }
            outcome.fold(
                { callback.onResult(this@NeuroVerifyCall, it) },
                { callback.onFailure(this@NeuroVerifyCall, it as NeuroVerifyError) },
            )
        }
        attach(launched)
    }

    /** Cancels preparation, the upload, retry waits, and response processing. Safe to call repeatedly. */
    public fun cancel() {
        if (canceled.compareAndSet(false, true)) job.get()?.cancel()
    }

    private fun attach(running: Job?) {
        job.set(running)
        if (canceled.get()) running?.cancel()
    }

    private fun markStarted() {
        check(started.compareAndSet(false, true)) { "A NeuroVerifyCall can only be run once." }
    }
}
