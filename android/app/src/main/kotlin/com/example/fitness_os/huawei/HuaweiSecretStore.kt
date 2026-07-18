package com.example.fitness_os.huawei

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Secrets only — never Flutter prefs. MAC/name identity lives in Dart.
 */
class HuaweiSecretStore(context: Context) {
    private val prefs: SharedPreferences

    init {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        prefs = EncryptedSharedPreferences.create(
            context,
            "huawei_secrets",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun hasSecrets(): Boolean {
        return !prefs.getString(KEY_AUTH_MATERIAL, null).isNullOrEmpty() ||
            !prefs.getString(KEY_USER_ID, null).isNullOrEmpty() ||
            !prefs.getString(KEY_PHONE_MAC, null).isNullOrEmpty()
    }

    fun getUserId(): String? = prefs.getString(KEY_USER_ID, null)

    fun setUserId(userId: String?) {
        prefs.edit().apply {
            if (userId.isNullOrBlank()) remove(KEY_USER_ID)
            else putString(KEY_USER_ID, userId.trim())
            apply()
        }
    }

    /** Phone Classic BT identity MAC override (Android privacy MAC workaround). */
    fun getPhoneMac(): String? = prefs.getString(KEY_PHONE_MAC, null)

    fun setPhoneMac(mac: String?) {
        prefs.edit().apply {
            if (mac.isNullOrBlank()) remove(KEY_PHONE_MAC)
            else putString(KEY_PHONE_MAC, normalizeMac(mac))
            apply()
        }
    }

    fun setAuthMaterial(value: String?) {
        prefs.edit().apply {
            if (value.isNullOrBlank()) remove(KEY_AUTH_MATERIAL)
            else putString(KEY_AUTH_MATERIAL, value)
            apply()
        }
    }

    fun getAuthMaterial(): String? = prefs.getString(KEY_AUTH_MATERIAL, null)

    /** Stable fake Android-ID token used in Security Negotiation (HiChain probe). */
    fun getOrCreateAndroidIdToken(): String {
        val existing = prefs.getString(KEY_ANDROID_ID_TOKEN, null)
        if (!existing.isNullOrBlank()) return existing
        val generated = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }
            .joinToString("") { "%02X".format(it) }
        prefs.edit().putString(KEY_ANDROID_ID_TOKEN, generated).apply()
        return generated
    }

    fun clearSecrets() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_USER_ID = "huawei_user_id"
        private const val KEY_AUTH_MATERIAL = "huawei_auth_material"
        private const val KEY_PHONE_MAC = "huawei_phone_mac"
        private const val KEY_ANDROID_ID_TOKEN = "huawei_android_id_token"

        fun normalizeMac(raw: String): String {
            val hex = raw.uppercase().replace(Regex("[^0-9A-F]"), "")
            require(hex.length == 12) { "MAC must be 12 hex digits" }
            return hex.chunked(2).joinToString(":")
        }

        fun looksLikeMac(raw: String): Boolean {
            val hex = raw.uppercase().replace(Regex("[^0-9A-F]"), "")
            return hex.length == 12
        }
    }
}
