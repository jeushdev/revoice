package com.larpcode.revise.backend

/** Only the CRM worker opens/closes native resources. Cancellation may come from another thread. */
fun interface CrmRuntimeFactory {
    fun open(): CrmRuntime
}

interface CrmRuntime : AutoCloseable {
    fun newConversation(maxOutputTokens: Int): CrmConversation
}

interface CrmConversation : AutoCloseable {
    /** Blocks until the terminal native callback; never returns while inference is still active. */
    fun generate(prompt: String): CrmOutput
    /** Thread safe, also effective when requested immediately before generate. */
    fun cancel()
}

data class CrmOutput(val text: String, val decodeTokens: Int)
