package com.larpcode.revise.backend

/** Safe for channel delivery. Never attach SDK exceptions containing user text. */
class BackendFailure(val code: String, message: String) : Exception(message) {
    companion object {
        fun invalidState(message: String) = BackendFailure("invalid_state", message)
        fun modelMissing(message: String) = BackendFailure("model_missing", message)
        fun inferenceFailed(message: String = "Local CRM inference failed.") =
            BackendFailure("inference_failed", message)
    }
}
