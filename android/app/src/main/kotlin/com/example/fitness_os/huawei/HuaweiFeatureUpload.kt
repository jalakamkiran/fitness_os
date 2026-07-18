package com.example.fitness_os.huawei

import android.util.Log
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.Locale

/**
 * Clean-room Gate A features-file upload (GB FeatureManager behavioral path).
 *
 * After DataSync configAction=2 handshake (`"01"`), GB uploads
 * `feature_<CC>_device.txt` via FileUpload service `0x28`, then notifies with
 * configAction=1. Skipping the upload leaves the watch retrying and then
 * tearing down the secure session (observed GCM MAC fail + RFCOMM close).
 *
 * Wire shapes from public FileUpload / DataSync packet layouts — not AGPL paste.
 */
class HuaweiFeatureUpload(
    private val sendEncrypted: (HuaweiFraming.Frame) -> Unit,
    /** Encrypt [plainBody] as 7C/7D/7E under svc/cmd (session crypto). */
    private val sendEncryptedRawBody: (serviceId: Int, commandId: Int, plainBody: ByteArray) -> Unit,
    /** Send svc/cmd + raw body with no TLV/crypto (no_encrypt=1 path). */
    private val sendRawBody: (serviceId: Int, commandId: Int, plainBody: ByteArray) -> Unit,
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        const val SVC_FILE = 0x28
        private const val CMD_FILE_INFO = 0x02
        private const val CMD_FILE_HASH = 0x03
        private const val CMD_FILE_CONSULT = 0x04
        private const val CMD_FILE_NEXT_CHUNK = 0x05
        private const val CMD_FILE_CHUNK_SEND = 0x06
        private const val CMD_FILE_RESULT = 0x07
        private const val CMD_FILE_DEVICE_ERROR = 0x08
        private const val FILE_TYPE_FEATURES: Byte = 0x0F
        private const val FEATURES_VERSION = 1
        private const val FEATURE_CONFIG_ID = 900_100_007
        private const val ACTION_NOTIFY = 1
        private const val ACTION_REQUEST = 2
        private const val SVC_DATASYNC = 0x37
        private const val CMD_DATASYNC_CONFIG = 0x01
        private const val PKG_FEATURE_MANAGER = "featureManager"
        private const val PKG_CONFIG_MANAGER = "hw.unitedevice.configManager"
        private const val TAG_RESULT = 0x7F
    }

    private enum class State {
        Idle,
        InfoSent,
        HashSent,
        Transferring,
        Done,
        Failed,
    }

    @Volatile
    private var state = State.Idle
    private var fileBytes: ByteArray = ByteArray(0)
    private var fileName: String = ""
    private var countryCode: String = "IN"
    private var fileId: Byte = 0
    private var encryptChunks: Boolean = true
    private var unitSize: Int = 256

    val isActive: Boolean
        get() = state == State.InfoSent || state == State.HashSent || state == State.Transferring

    val isDone: Boolean
        get() = state == State.Done

    fun reset() {
        state = State.Idle
        fileBytes = ByteArray(0)
        fileName = ""
        fileId = 0
        encryptChunks = true
        unitSize = 256
    }

    /**
     * GB sendCommonFeaturesData(action=2,"01") then SendFileUploadInfo.
     * No-ops if an upload is already in flight or finished this session.
     */
    fun startAfterAction2Handshake(sendAction2Ack: () -> Unit) {
        when (state) {
            State.Done -> {
                Log.d(TAG, "feature-upload already done — ignore action=2")
                return
            }
            State.InfoSent, State.HashSent, State.Transferring -> {
                Log.d(TAG, "feature-upload in progress ($state) — ignore action=2")
                return
            }
            State.Failed, State.Idle -> Unit
        }

        countryCode = Locale.getDefault().country.ifBlank { "IN" }.uppercase(Locale.ROOT)
        fileName = "feature_${countryCode}_device.txt"
        fileBytes = buildFeaturesFileJson(countryCode).toByteArray(Charsets.UTF_8)
        Log.i(
            TAG,
            "feature-upload start name=$fileName size=${fileBytes.size} sha=${sha256(fileBytes).toHex()}",
        )

        sendAction2Ack()
        state = State.InfoSent
        sendFileInfo()
    }

    /** Handle decrypted FileUpload (`svc=0x28`) frames. */
    fun onFileUploadFrame(frame: HuaweiFraming.Frame) {
        if (frame.serviceId != SVC_FILE) return
        if (state == State.Idle || state == State.Done || state == State.Failed) return

        when (frame.commandId) {
            CMD_FILE_INFO -> {
                val code = resultCode(frame)
                if (code != null && code != HuaweiPacketCrypto.RESULT_OK) {
                    Log.w(TAG, "feature-upload FileInfo rejected result=$code")
                    state = State.Failed
                } else {
                    Log.d(TAG, "feature-upload FileInfo ok — waiting for fileId")
                }
            }
            CMD_FILE_HASH -> {
                val id = frame.tlvs.firstOrNull { it.tag == 0x01 }?.value?.firstOrNull() ?: run {
                    Log.w(TAG, "feature-upload FileHash missing fileId")
                    return
                }
                fileId = id
                Log.i(TAG, "feature-upload fileId=${fileId.toInt() and 0xFF} — tx hash")
                sendFileHash()
                state = State.HashSent
            }
            CMD_FILE_CONSULT -> {
                unitSize = asInt(frame, 0x05)?.takeIf { it > 0 } ?: 256
                val noEnc = frame.tlvs.firstOrNull { it.tag == 0x09 }?.value?.firstOrNull()?.toInt()?.and(0xFF) ?: 0
                encryptChunks = noEnc == 0
                Log.i(
                    TAG,
                    "feature-upload consult unitSize=$unitSize encryptChunks=$encryptChunks — tx ack",
                )
                sendConsultAck()
                state = State.Transferring
            }
            CMD_FILE_NEXT_CHUNK -> {
                val uploaded = asInt(frame, 0x02) ?: 0
                val chunkSize = asInt(frame, 0x03) ?: unitSize
                Log.i(TAG, "feature-upload next-chunk offset=$uploaded size=$chunkSize")
                sendChunk(uploaded, chunkSize)
            }
            CMD_FILE_RESULT -> {
                val status = frame.tlvs.firstOrNull { it.tag == 0x02 }?.value?.firstOrNull()
                    ?.toInt()?.and(0xFF) ?: -1
                // GB always completes on FileUploadResult; status is logged for diagnosis.
                Log.i(TAG, "feature-upload result status=$status — tx complete + notify")
                sendUploadComplete()
                sendAction1Notify()
                state = State.Done
            }
            CMD_FILE_DEVICE_ERROR -> {
                val code = asInt(frame, 0x02) ?: -1
                Log.w(TAG, "feature-upload device error code=$code")
                state = State.Failed
            }
        }
    }

    private fun sendFileInfo() {
        val tlvs = listOf(
            HuaweiFraming.Tlv(0x01, fileName.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x02, HuaweiPacketCrypto.intBe(fileBytes.size)),
            HuaweiFraming.Tlv(0x03, byteArrayOf(FILE_TYPE_FEATURES)),
        )
        Log.i(TAG, "tx file-info name=$fileName size=${fileBytes.size} type=0x0f")
        sendEncrypted(HuaweiFraming.Frame(SVC_FILE, CMD_FILE_INFO, tlvs))
    }

    private fun sendFileHash() {
        val tlvs = listOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(fileId)),
            HuaweiFraming.Tlv(0x03, sha256(fileBytes)),
        )
        sendEncrypted(HuaweiFraming.Frame(SVC_FILE, CMD_FILE_HASH, tlvs))
    }

    private fun sendConsultAck() {
        val tlvs = mutableListOf(
            HuaweiFraming.Tlv(TAG_RESULT, HuaweiPacketCrypto.intBe(HuaweiPacketCrypto.RESULT_OK)),
            HuaweiFraming.Tlv(0x01, byteArrayOf(fileId)),
        )
        if (!encryptChunks) {
            tlvs += HuaweiFraming.Tlv(0x09, byteArrayOf(0x01))
        }
        sendEncrypted(HuaweiFraming.Frame(SVC_FILE, CMD_FILE_CONSULT, tlvs))
    }

    private fun sendChunk(offset: Int, requestedSize: Int) {
        if (offset < 0 || offset > fileBytes.size) {
            Log.w(TAG, "feature-upload bad offset=$offset")
            return
        }
        val size = minOf(requestedSize.coerceAtLeast(1), fileBytes.size - offset, unitSize.coerceAtLeast(1))
        if (size <= 0) {
            Log.d(TAG, "feature-upload no bytes left at offset=$offset")
            return
        }
        val content = fileBytes.copyOfRange(offset, offset + size)
        // GB serializeFileChunk: one sub-packet when content fits unitSize.
        val payload = ByteBuffer.allocate(6 + content.size)
            .put(fileId)
            .put(0) // sub-packet index within this chunk request
            .putInt(offset)
            .put(content)
            .array()
        Log.i(TAG, "tx file-chunk offset=$offset size=$size encrypt=$encryptChunks")
        if (encryptChunks) {
            sendEncryptedRawBody(SVC_FILE, CMD_FILE_CHUNK_SEND, payload)
        } else {
            sendRawBody(SVC_FILE, CMD_FILE_CHUNK_SEND, payload)
        }
    }

    private fun sendUploadComplete() {
        val tlvs = listOf(
            HuaweiFraming.Tlv(TAG_RESULT, HuaweiPacketCrypto.intBe(HuaweiPacketCrypto.RESULT_OK)),
            HuaweiFraming.Tlv(0x01, byteArrayOf(fileId)),
        )
        sendEncrypted(HuaweiFraming.Frame(SVC_FILE, CMD_FILE_RESULT, tlvs))
    }

    /** GB sendCommonFeaturesData(action=1, notify JSON) after upload complete. */
    private fun sendAction1Notify() {
        val json = buildNotifyJson(countryCode, fileName)
        val item = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(FEATURE_CONFIG_ID)),
                HuaweiFraming.Tlv(0x06, byteArrayOf(ACTION_NOTIFY.toByte())),
                HuaweiFraming.Tlv(0x07, json.toByteArray(Charsets.UTF_8)),
            ),
        )
        val list = HuaweiFraming.encodeTlvs(
            listOf(HuaweiFraming.Tlv(0x84, item)),
        )
        val reply = listOf(
            HuaweiFraming.Tlv(0x01, PKG_CONFIG_MANAGER.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x02, PKG_FEATURE_MANAGER.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x83, list),
        )
        Log.i(TAG, "tx datasync featureManager action=1 notify file=$fileName")
        sendEncrypted(HuaweiFraming.Frame(SVC_DATASYNC, CMD_DATASYNC_CONFIG, reply))
    }

    private fun resultCode(frame: HuaweiFraming.Frame): Int? {
        val code = frame.tlvs.firstOrNull { it.tag == TAG_RESULT }?.value ?: return null
        if (code.size < 4) return null
        return ((code[0].toInt() and 0xFF) shl 24) or
            ((code[1].toInt() and 0xFF) shl 16) or
            ((code[2].toInt() and 0xFF) shl 8) or
            (code[3].toInt() and 0xFF)
    }

    private fun asInt(frame: HuaweiFraming.Frame, tag: Int): Int? {
        val v = frame.tlvs.firstOrNull { it.tag == tag }?.value ?: return null
        return when (v.size) {
            1 -> v[0].toInt() and 0xFF
            2 -> ((v[0].toInt() and 0xFF) shl 8) or (v[1].toInt() and 0xFF)
            4 -> ((v[0].toInt() and 0xFF) shl 24) or
                ((v[1].toInt() and 0xFF) shl 16) or
                ((v[2].toInt() and 0xFF) shl 8) or
                (v[3].toInt() and 0xFF)
            else -> null
        }
    }

    private fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)

    private fun ByteArray.toHex(): String =
        joinToString("") { b -> "%02x".format(b) }

    /**
     * Minimal features JSON matching GB FeatureManager shape (country-scoped).
     * Content is behavioral oracle only — not copied from AGPL sources.
     */
    private fun buildFeaturesFileJson(country: String): String {
        // Compact JSON — watch accepts empty-ish feature lists during pair finalize;
        // structure mirrors the public FeatureManager notify/file contract.
        return """{"featureList":[{"devPackageName":"com.huawei.health.pwvdetection","support":1,"extInfo":{"medical":false}},{"devPackageName":"com.huawei.health.bloodpressure","support":1,"extInfo":{"ABPM":[135,85,120,70,130,80],"local":2}},{"devPackageName":"com.huawei.watch.health.ecganalysis","support":1,"extInfo":{"medical":false}},{"devPackageName":"com.huawei.health.healthcheck","support":1,"extInfo":{"checkItem":23}},{"devPackageName":"com.huawei.hmos.watch.emotional","support":1},{"devPackageName":"com.huawei.hmos.watch.plateaucare","support":1,"extInfo":{"medical":false}},{"devPackageName":"com.huawei.watch.health.arrhythmia","support":1,"extInfo":{"medical":false}}],"country":"$country","ver":$FEATURES_VERSION,"name":"feature_${country}_device"}"""
    }

    private fun buildNotifyJson(country: String, name: String): String {
        return """{"filterCondition":[{"filterCountry":"$country"}],"configName":"com.huawei.health_deviceFeature_config","fileData":[{"version":$FEATURES_VERSION,"fileName":"$name"}]}"""
    }

    /** Build action=2 `"01"` ConfigCommand TLVs (caller encrypts/sends). */
    fun action2AckTlvs(): List<HuaweiFraming.Tlv> {
        val item = HuaweiFraming.encodeTlvs(
            listOf(
                HuaweiFraming.Tlv(0x05, HuaweiPacketCrypto.intBe(FEATURE_CONFIG_ID)),
                HuaweiFraming.Tlv(0x06, byteArrayOf(ACTION_REQUEST.toByte())),
                HuaweiFraming.Tlv(0x07, byteArrayOf(0x30, 0x31)),
            ),
        )
        val list = HuaweiFraming.encodeTlvs(
            listOf(HuaweiFraming.Tlv(0x84, item)),
        )
        return listOf(
            HuaweiFraming.Tlv(0x01, PKG_CONFIG_MANAGER.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x02, PKG_FEATURE_MANAGER.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x83, list),
        )
    }
}
