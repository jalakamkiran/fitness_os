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
            !prefs.getString(KEY_USER_ID, null).isNullOrEmpty()
    }

    fun getUserId(): String? = prefs.getString(KEY_USER_ID, null)

    fun setUserId(userId: String?) {
        prefs.edit().apply {
            if (userId.isNullOrBlank()) remove(KEY_USER_ID)
            else putString(KEY_USER_ID, userId.trim())
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

    fun clearSecrets() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_USER_ID = "huawei_user_id"
        private const val KEY_AUTH_MATERIAL = "huawei_auth_material"
    }
}
