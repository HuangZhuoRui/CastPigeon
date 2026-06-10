package com.suseoaa.castpigeon.shared

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.json.Json

@Serializable
data class PeerMessage(
    @SerialName("type")
    val type: String,

    @SerialName("deviceName")
    val deviceName: String? = null,

    @SerialName("deviceId")
    val deviceId: String? = null,

    @SerialName("message")
    val message: String? = null,

    @SerialName("id")
    val id: String? = null,

    @SerialName("appName")
    val appName: String? = null,

    @SerialName("title")
    val title: String? = null,

    @SerialName("content")
    val content: String? = null,

    @SerialName("timestamp")
    val timestamp: Long? = null,
        @SerialName("reason")
        val reason: String? = null
) {
    companion object {
        fun fromJson(jsonString: String): PeerMessage {
            return json.decodeFromString(serializer(), jsonString)
        }

        fun toJson(message: PeerMessage): String {
            return json.encodeToString(serializer(), message)
        }

        private val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            isLenient = true
        }
    }
}
