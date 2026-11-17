package com.example.fitness_os.huawei

import android.os.SystemClock
import android.util.Log
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import com.example.fitness_os.observability.HuaweiSyncBreadcrumbs

/**
 * Gate A session orchestration (clean-room).
 *
 * Mode from link-params tag 0x07 (deviceSupportType):
 * - 0 → Normal LPv2 (MIT)
 * - 4 → HiChain3 ISO exchange (cmd 0x28) with standard crypto
 */
class HuaweiSession(
    private val transport: RfcommTransport,
    private val secrets: HuaweiSecretStore,
    private val emit: (Map<String, Any?>) -> Unit,
    /** App files root for TruSleep side-files (optional — skip persist when null). */
    private val appFilesDir: (() -> java.io.File)? = null,
    private val isSyncHeld: () -> Boolean = { false },
) {
    companion object {
        private const val TAG = "FOS_HUAWEI"
        private const val SVC = 0x01
        private const val CMD_LINK_PARAMS = 0x01
        private const val CMD_AUTH = 0x13
        private const val CMD_BOND_PARAMS = 0x0F
        private const val CMD_BOND = 0x0E
        private const val CMD_DEVICE_STATUS = 0x16
        private const val CMD_SECURITY_NEGO = 0x33
        private const val CMD_PRODUCT_INFO = 0x07
        private const val CMD_SET_TIME = 0x05
        private const val CMD_SUPPORTED_SERVICES = 0x02
        private const val CMD_SUPPORTED_COMMANDS = 0x03
        private const val CMD_BATTERY = 0x08
        private const val CMD_SETUP_DEVICE_STATUS = 0x3E
        private const val CMD_PHONE_INFO = 0x10
        private const val CMD_DATE_FORMAT = 0x04
        private const val CMD_EXPAND_CAPABILITY = 0x37
        private const val CMD_ACCEPT_AGREEMENT = 0x30
        private const val CMD_SETTING_RELATED = 0x31
        private const val CMD_TIME_ZONE_ID = 0x32
        private const val CMD_CONNECT_STATUS = 0x35
        private const val CMD_REVERSE_CAPABILITIES = 0x3F
        private const val SVC_LOCALE = 0x0C
        private const val CMD_SET_LANGUAGE = 0x01
        /** AccountRelated (GB) — Extended Account + Country Code live here. */
        private const val SVC_ACCOUNT = 0x1A
        private const val CMD_EXTENDED_ACCOUNT = 0x05
        private const val CMD_ACCOUNT_SWITCH = 0x06
        private const val CMD_COUNTRY_CODE = 0x0A
        /** ExpandCapability bit for diff-account pairing optimization (GB 0xac). */
        private const val EXPAND_BIT_ACCOUNT_PAIR_OPT = 0xac
        private const val SVC_MUSIC = 0x25
        private const val CMD_MUSIC_STATUS = 0x01
        private const val CMD_MUSIC_CONTROL = 0x03
        /** GB GetMusicInfoParams — empty-tag capability probe. */
        private const val CMD_MUSIC_INFO_PARAMS = 0x04
        /** GB GetExtendedMusicInfoParams / Negotiation — empty-tag probe. */
        private const val CMD_MUSIC_EXTENDED_PARAMS = 0x0D
        private const val SVC_P2P = 0x34
        private const val CMD_P2P = 0x01
        private const val P2P_CMD_ACK = 0x03
        private const val P2P_ACK_CODE = 0xca
        /**
         * DataSync / UniteDevice (GB `DataSync.id = 0x37`).
         * Cmds: 0x01 config, 0x02 event, 0x03 data, 0x04 dict.
         *
         * Do **not** blanket-ACK with `t=7f:100000` — that poisoned GT5 sessions after
         * music-params succeeded (watch closed RFCOMM). GB FeatureManager answers
         * `featureManager` configAction=2 with a real ConfigCommand payload.
         */
        private const val SVC_DATASYNC = 0x37
        private const val CMD_DATASYNC_CONFIG = 0x01
        private const val TAG_RESULT = 0x7F
        private const val TAG_DATASYNC_SRC = 0x01
        private const val TAG_DATASYNC_DST = 0x02
        private const val TAG_DATASYNC_CONFIG_LIST = 0x83
        private const val TAG_DATASYNC_CONFIG_ITEM = 0x84
        private const val TAG_DATASYNC_CONFIG_ID = 0x05
        private const val TAG_DATASYNC_CONFIG_ACTION = 0x06
        private const val TAG_DATASYNC_CONFIG_DATA = 0x07
        private const val PKG_FEATURE_MANAGER = "featureManager"
        /** GB HuaweiDataSyncFeatureManager config id for device-feature config. */
        private const val FEATURE_CONFIG_ID = 900_100_007
        private const val FEATURE_CONFIG_ACTION_REQUEST = 2
        private const val TAG_MUSIC_BUTTON = 0x01
        private const val TAG_MUSIC_VOLUME = 0x02
        private const val MUSIC_BUTTON_EXIT = 100
        private const val RESULT_SUCCESS = 100000
        private const val RESULT_SYSTEM_BUSY = 100004
        private const val DATE_YEAR_FIRST = 0x01
        private const val TIME_HOURS_24 = 0x02
        private const val MEASUREMENT_METRIC: Byte = 0x00

        /**
         * Forced companion app-version integer for PhoneInfo tag 0x11.
         * Watches expect a Health-compatible version code during pair finalize.
         */
        private const val PHONE_INFO_APP_VERSION = 1_400_106_310
        private const val AUTH_TIMEOUT_MS = 20_000L
        private const val HICHAIN_STEP_TIMEOUT_MS = 35_000L
        private const val CONFIGURE_TIMEOUT_MS = 12_000L
        private const val LISTEN_BEFORE_SEND_MS = 800L

        /** Product-info empty-tag probe set used for Classic BR watches. */
        private val PRODUCT_INFO_TAGS = intArrayOf(
            0x01, 0x02, 0x07, 0x09, 0x0A, 0x11, 0x12, 0x16,
            0x1A, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23,
        )

        /**
         * Service-ID probe list sent in supported-services (cmd 0x02).
         * Wire values from public LPv2 / community captures — not AGPL source.
         */
        private val KNOWN_SUPPORTED_SERVICES = byteArrayOf(
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A,
            0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14,
            0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1D, 0x20,
            0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2D, 0x2E,
            0x30, 0x32, 0x33, 0x34, 0x35, 0x37,
        )

        /**
         * SupportedCommands probe map (GB DeviceConfig.SupportedCommands shape).
         * Values are command-id lists asked per active service — not AGPL paste.
         * Includes 0x3F on svc 0x01 so ReverseCapabilities can be discovered.
         */
        private val COMMANDS_PROBE: Map<Int, ByteArray> = mapOf(
            0x01 to byteArrayOf(
                0x04, 0x07, 0x08, 0x09, 0x0A, 0x0D, 0x0E, 0x10, 0x11, 0x12, 0x13, 0x14,
                0x1A, 0x1B, 0x1D, 0x21, 0x22, 0x23, 0x24, 0x29, 0x2A, 0x2B, 0x2E, 0x2F,
                0x30, 0x31, 0x32, 0x35, 0x36, 0x37, 0x3E, 0x3F,
            ),
            0x02 to byteArrayOf(0x01, 0x04, 0x05, 0x06, 0x07, 0x08),
            0x07 to byteArrayOf(
                0x01, 0x03, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0E, 0x10, 0x13, 0x15,
                0x16, 0x17, 0x18, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x21, 0x22, 0x23, 0x24,
                0x25, 0x28, 0x29,
            ),
            0x0C to byteArrayOf(0x01),
            0x1A to byteArrayOf(0x01, 0x03, 0x05, 0x06, 0x07, 0x0A),
            0x25 to byteArrayOf(0x01, 0x02, 0x03, 0x04, 0x0D, 0x0E),
            0x27 to byteArrayOf(0x01, 0x0E),
            0x2A to byteArrayOf(0x01, 0x06),
            0x34 to byteArrayOf(0x01),
            0x35 to byteArrayOf(0x01, 0x03, 0x04),
        )

        /** GB ReverseCapabilities phone→watch bitmap (master oracle). */
        private val REVERSE_CAPABILITIES = byteArrayOf(
            0xFD.toByte(), 0xF7.toByte(), 0x33, 0xFA.toByte(), 0x29, 0x37,
        )

        fun supportTypeLabel(type: Int): String = when (type) {
            0 -> "Normal"
            1, 3 -> "HiChain"
            2, 8 -> "HiChainLite"
            4 -> "HiChain3"
            else -> "Unknown($type)"
        }

        fun isHiChainFamily(type: Int): Boolean =
            type == 1 || type == 2 || type == 3 || type == 4 || type == 8
    }

    private val inbound = AtomicReference<CountDownLatch?>(null)
    private val frameQueue = ArrayDeque<HuaweiFraming.Frame>()
    private val reassembly = ByteArrayOutputStream()
    private val sliceAcc = ByteArrayOutputStream()
    private var assemblingSlices = false
    private val bytesReceived = AtomicInteger(0)
    private val frameLock = Any()
    private var sliceSize = 0x00F4

    /** Set after auth/bind — enables encrypted post-bind configure. */
    private var sessionKey: ByteArray? = null
    private var deviceSupportType: Int = 0
    private var encryptMethod: Int = 0
    private var encryptionEnabled: Boolean = false
    private val encryptionCounter = AtomicLong(0)
    private var expandCapabilities: ByteArray? = null
    /** Per-service command support from SupportedCommands `0x01:0x03`. */
    private var commandsByService: Map<Int, Set<Int>> = emptyMap()
    /** Gate FeatureManager FileUpload until Extended Account has been attempted. */
    @Volatile
    private var accountConfigureDone: Boolean = false
    @Volatile
    private var pendingFeatureManagerAction2: Boolean = false

    private val featureUpload = HuaweiFeatureUpload(
        sendEncrypted = { frame -> sendEncryptedNoWait(frame) },
        sendEncryptedRawBody = { svc, cmd, body -> sendEncryptedRawBody(svc, cmd, body) },
        sendRawBody = { svc, cmd, body ->
            try {
                transport.write(HuaweiFraming.encodeRawBody(svc, cmd, body))
            } catch (e: Exception) {
                Log.w(TAG, "sendRawBody failed: ${e.message}")
            }
        },
    )

    /** Hard-off FeatureUpload (`0x28`) while product Sync is in flight. */
    @Volatile
    private var productSyncActive: Boolean = false

    @Volatile
    private var liftEnabled: Boolean = false
    private val liftMsgIdCounter = AtomicInteger(0x4C00)
    private val liftP2pSeq = AtomicInteger(1)
    @Volatile
    private var cachedNotifyConstraints: NotifyConstraints? = null
    @Volatile
    private var lastLiftNotification: HuaweiNotifyLift.LastSentNotification? = null
    private val pendingLiftSend = AtomicReference<HuaweiFraming.Frame?>(null)

    /**
     * Last zone we pushed to the watch (set-time / timezone-id). Used to format
     * TruSleep unix consistently for any phone region.
     */
    @Volatile
    private var syncedWatchZone: HuaweiPacketCrypto.WatchZone =
        HuaweiPacketCrypto.WatchZone.fromPhone()
    /** Last set-time skew (deviceUnix − phoneUnix); null until first echo. */
    private var lastWatchSkewSec: Int? = null
    private var lastWatchDeviceUnix: Int? = null

    fun currentWatchZone(): HuaweiPacketCrypto.WatchZone = syncedWatchZone

    private fun watchClockSnapshotMap(): Map<String, Any?> {
        val z = syncedWatchZone
        return buildMap {
            put("zoneId", z.zoneId)
            put("offsetSec", z.offsetSec)
            put("offsetLabel", z.formatOffsetLabel())
            put("phoneUnix", (System.currentTimeMillis() / 1000L).toInt())
            lastWatchSkewSec?.let { put("skewSec", it) }
            lastWatchDeviceUnix?.let { put("deviceUnix", it) }
        }
    }

    /**
     * Gate B: Count → Totals over the authenticated session.
     * Caller must already have a ready encrypted session (post authenticate).
     *
     * [enrichStartUnix] gates hint-based Data/Pace/Swim; Count uses [startUnix].
     * Defaults to [startUnix] when omitted (incremental Sync).
     */
    fun syncWorkouts(
        startUnix: Long,
        endUnix: Long,
        enrichStartUnix: Long = startUnix,
    ): Map<String, Any?> {
        if (sessionKey == null || !encryptionEnabled) {
            Log.w(TAG, "workout-sync rejected — session not ready")
            return mapOf(
                "status" to "not_ready",
                "message" to "Session not ready — reconnect first",
                "workouts" to emptyList<Map<String, Any?>>(),
            )
        }
        productSyncActive = true
        try {
            return HuaweiWorkoutSync(
                exchangeEncrypted = { req, svc, cmd, timeout ->
                    exchangeEncrypted(req, svc, cmd, timeout)
                },
                persistWorkoutSamples = { id, bytes -> persistWorkoutSampleFile(id, bytes) },
                persistWorkoutLeftovers = { id, bytes -> persistWorkoutLeftoverFile(id, bytes) },
            ).sync(startUnix, endUnix, enrichStartUnix)
        } finally {
            productSyncActive = false
        }
    }

    /**
     * Activity Sync: FitnessData sleep + daily HR (message path), then
     * non-blocking TruSleep FileDownload probe (soft-fail).
     * Caller must hold the shared Sync lock.
     */
    fun syncActivity(
        startUnix: Long,
        endUnix: Long,
        skipTruSleepSoft: Boolean = false,
        skipAutoHrSoft: Boolean = false,
    ): Map<String, Any?> {
        if (sessionKey == null || !encryptionEnabled) {
            Log.w(TAG, "activity-sync rejected — session not ready")
            return mapOf(
                "status" to "not_ready",
                "message" to "Session not ready — reconnect first",
                "sleepSessions" to emptyList<Map<String, Any?>>(),
                "dailyHrSamples" to emptyList<Map<String, Any?>>(),
                "completedContainers" to emptyList<String>(),
                "enableSkipped" to false,
            )
        }
        productSyncActive = true
        try {
            // Refresh phone→watch clock/zone before sleep file decode.
            syncWatchTimeAndZone(reason = "activity-sync")
            return fitnessDataSync().sync(
                startUnix,
                endUnix,
                skipTruSleepSoft = skipTruSleepSoft,
                skipAutoHrSoft = skipAutoHrSoft,
            )
        } finally {
            productSyncActive = false
        }
    }

    /**
     * Explicit auto-tracking enable (TruSleep / auto-HR / auto-SpO2).
     * Caller must hold the shared Sync lock. FeatureUpload hard-off for the batch.
     */
    fun enableAutoTracking(): Map<String, Any?> {
        if (sessionKey == null || !encryptionEnabled) {
            Log.w(TAG, "enable-auto rejected — session not ready")
            return mapOf(
                "status" to "not_ready",
                "message" to "Session not ready — reconnect first",
                "overall" to "none_armed",
                "features" to emptyList<Map<String, Any?>>(),
            )
        }
        productSyncActive = true
        try {
            return fitnessDataSync().enableAutoTracking()
        } finally {
            productSyncActive = false
        }
    }

    /**
     * Debug-only post-Sync physio capture probe (dict → gated sleep_data → optional path-2).
     * Caller must hold [HuaweiSyncLock]. Never merges into Flutter TruSleep SoT.
     */
    fun probePhysioCapture(
        includeDict: Boolean = true,
        includeSleepData: Boolean = true,
        includePath2Intervals: Boolean = false,
        startUnix: Long = 0L,
        endUnix: Long = System.currentTimeMillis() / 1000L,
    ): Map<String, Any?> {
        if (sessionKey == null || !encryptionEnabled) {
            Log.w(TAG, "physio-probe rejected — session not ready")
            return mapOf(
                "status" to "not_ready",
                "message" to "Session not ready — reconnect first",
                "feedsProductSleepSot" to false,
            )
        }
        productSyncActive = true
        try {
            val start = startUnix.toInt().coerceAtLeast(0)
            val end = endUnix.toInt().coerceAtLeast(start)
            return HuaweiPhysioCaptureProbe(
                fileDownload = { diagnosticFileDownload(persistDiagnosticBodies = false) },
                listenFeatureUploadSequence = { timeoutMs ->
                    listenForSequenceFeatureUpload(timeoutMs)
                },
                pullIntervalProxy = if (includePath2Intervals) {
                    { s, e, intervals ->
                        fitnessDataSync().probeDailyHrIntervalProxy(
                            s.toLong(),
                            e.toLong(),
                            sleepIntervals = intervals,
                        )
                    }
                } else {
                    null
                },
            ).run(
                HuaweiPhysioCaptureProbe.Options(
                    includeDict = includeDict,
                    includeSleepData = includeSleepData,
                    includePath2Intervals = includePath2Intervals,
                    startUnix = start,
                    endUnix = end,
                ),
            )
        } finally {
            productSyncActive = false
        }
    }

    /**
     * Debug-only: download `sleep_data.bin` and **persist** under
     * `vitals/sleep_files/sleep_data.bin` for offline structure work.
     * Never merges into Flutter TruSleep SoT. Caller must hold [HuaweiSyncLock].
     */
    fun persistSleepDataCapture(
        startUnix: Long = 0L,
        endUnix: Long = System.currentTimeMillis() / 1000L,
    ): Map<String, Any?> {
        if (sessionKey == null || !encryptionEnabled) {
            Log.w(TAG, "sleep-data-persist rejected — session not ready")
            return mapOf(
                "status" to "not_ready",
                "message" to "Session not ready — reconnect first",
                "feedsProductSleepSot" to false,
                "persisted" to false,
            )
        }
        productSyncActive = true
        try {
            val start = startUnix.toInt().coerceAtLeast(0)
            val end = endUnix.toInt().coerceAtLeast(start)
            val observed = diagnosticFileDownload(persistDiagnosticBodies = true)
                .downloadSleepDataStructureObserve(
                    startUnix = start,
                    endUnix = end,
                    persist = true,
                )
            val persisted = !observed.path.isNullOrEmpty()
            Log.i(
                TAG,
                "sleep-data-persist status=${observed.status} len=${observed.len} " +
                    "path=${observed.path} persisted=$persisted",
            )
            return buildMap {
                putAll(observed.toMap())
                put("feedsProductSleepSot", false)
                put("persisted", persisted)
                put(
                    "message",
                    when {
                        observed.status == "present" && persisted ->
                            "Saved sleep_data.bin (${observed.len} B)"
                        observed.status == "present" ->
                            "Downloaded but persist failed (${observed.reason})"
                        else ->
                            "sleep_data ${observed.status}" +
                                (observed.reason?.let { " ($it)" } ?: "")
                    },
                )
            }
        } finally {
            productSyncActive = false
        }
    }

    /**
     * Debug-only: download SLEEP_DETAILS SEQUENCE_DATA and **persist** under
     * `vitals/sleep_files/sequence_data.bin` for offline decode.
     * Never merges into Flutter TruSleep SoT. Caller must hold [HuaweiSyncLock].
     */
    fun persistSleepDetailsSequenceCapture(
        startUnix: Long = 0L,
        endUnix: Long = System.currentTimeMillis() / 1000L,
    ): Map<String, Any?> {
        if (sessionKey == null || !encryptionEnabled) {
            Log.w(TAG, "sleep-dict-persist rejected — session not ready")
            return mapOf(
                "status" to "not_ready",
                "message" to "Session not ready — reconnect first",
                "feedsProductSleepSot" to false,
                "persisted" to false,
            )
        }
        productSyncActive = true
        try {
            val start = startUnix.toInt().coerceAtLeast(0)
            val end = endUnix.toInt().coerceAtLeast(start)
            val observed = diagnosticFileDownload(persistDiagnosticBodies = true)
                .downloadSleepDetailsSequenceObserve(
                    startUnix = start,
                    endUnix = end,
                    persist = true,
                )
            val persisted = !observed.path.isNullOrEmpty()
            Log.i(
                TAG,
                "sleep-dict-persist status=${observed.status} len=${observed.len} " +
                    "path=${observed.path} persisted=$persisted " +
                    "overnightKeys=${observed.overnightSummaryKeys}",
            )
            return buildMap {
                putAll(observed.toMap())
                put("feedsProductSleepSot", false)
                put("persisted", persisted)
                put("dictId", HuaweiFileDownload.DICT_SLEEP_DETAILS_CLASS)
                put(
                    "message",
                    when {
                        observed.status == "present" && persisted ->
                            "Saved sequence_data.bin (${observed.len} B) " +
                                "keys=${observed.overnightSummaryKeys}"
                        observed.status == "present" ->
                            "Downloaded but persist failed (${observed.reason})"
                        else ->
                            "sequence_data ${observed.status}" +
                                (observed.reason?.let { " ($it)" } ?: "")
                    },
                )
            }
        } finally {
            productSyncActive = false
        }
    }

    /** Live FileDownload collaborator for diagnostic probes (not product Sync). */
    private fun diagnosticFileDownload(persistDiagnosticBodies: Boolean = false): HuaweiFileDownload =
        HuaweiFileDownload(
            exchangeEncrypted = { req, svc, cmd, timeout ->
                exchangeEncrypted(req, svc, cmd, timeout)
            },
            sendEncrypted = { frame -> sendEncryptedClearing(frame) },
            sendPlain = { frame -> sendPlainClearing(frame) },
            awaitRawBlock = { svc, timeout -> awaitFileDownloadBlock(svc, timeout) },
            isConnected = { transport.isConnected() },
            liveDownloadEnabled = true,
            persistFile = if (persistDiagnosticBodies) {
                { id, bytes ->
                    when (id) {
                        "sleep_data", "sequence_data" -> persistSleepFile(id, bytes)
                        else -> null
                    }
                }
            } else {
                null // wipe-only physio probe — never keep diagnostic bodies
            },
            formatUnix = { unix -> syncedWatchZone.formatUnix(unix) },
            watchZoneLabel = {
                "${syncedWatchZone.zoneId} ${syncedWatchZone.formatOffsetLabel()}"
            },
        )

    /**
     * Controlled listen for FeatureUpload (`0x28`) sequence / SLEEP_DETAILS-class push.
     * Does not start a phone-initiated upload. Privacy: route + len only.
     */
    private fun listenForSequenceFeatureUpload(timeoutMs: Long): Map<String, Any?>? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val remaining = (deadline - System.currentTimeMillis()).coerceAtLeast(1L)
            val frame = awaitServiceFrame(HuaweiFeatureUpload.SVC_FILE, remaining) ?: continue
            val name = frame.tlvs.firstOrNull { it.tag == 0x01 }?.value
                ?.toString(Charsets.UTF_8)
                .orEmpty()
            val lower = name.lowercase(Locale.US)
            if (lower.contains("sleep") || lower.contains("sequence")) {
                val size = frame.tlvs.firstOrNull { it.tag == 0x04 }?.value
                    ?.takeIf { it.size >= 4 }
                    ?.let { ByteBuffer.wrap(it).order(ByteOrder.BIG_ENDIAN).int }
                    ?: 0
                Log.i(TAG, "physio-probe FU listen hit route=$name len=$size")
                return mapOf(
                    "status" to "present",
                    "route" to name,
                    "len" to size,
                    "redactedKeys" to emptyList<String>(),
                    "overnightSummaryKeys" to emptyList<String>(),
                    "reason" to "fu_info_only_no_body",
                )
            }
        }
        return null
    }

    private fun fitnessDataSync(): HuaweiFitnessDataSync =
        HuaweiFitnessDataSync(
            exchangeEncrypted = { req, svc, cmd, timeout ->
                exchangeEncrypted(req, svc, cmd, timeout)
            },
            fetchBattery = {
                exchangeEncrypted(
                    HuaweiFraming.Frame(
                        SVC,
                        CMD_BATTERY,
                        listOf(HuaweiFraming.Tlv(0x01, byteArrayOf())),
                    ),
                    SVC,
                    CMD_BATTERY,
                    8_000L,
                )
            },
            isConnected = { transport.isConnected() },
            sleepFileDownload = {
                HuaweiFileDownload(
                    exchangeEncrypted = { req, svc, cmd, timeout ->
                        exchangeEncrypted(req, svc, cmd, timeout)
                    },
                    sendEncrypted = { frame -> sendEncryptedClearing(frame) },
                    sendPlain = { frame -> sendPlainClearing(frame) },
                    awaitRawBlock = { svc, timeout -> awaitFileDownloadBlock(svc, timeout) },
                    isConnected = { transport.isConnected() },
                    liveDownloadEnabled = true,
                    persistFile = { id, bytes -> persistSleepFile(id, bytes) },
                    formatUnix = { unix -> syncedWatchZone.formatUnix(unix) },
                    watchZoneLabel = {
                        "${syncedWatchZone.zoneId} ${syncedWatchZone.formatOffsetLabel()}"
                    },
                )
            },
            watchClockSnapshot = { watchClockSnapshotMap() },
        )

    /**
     * Push phone clock + zone to watch; persist zone for sleep formatting; log skew.
     */
    private fun syncWatchTimeAndZone(reason: String) {
        val now = System.currentTimeMillis()
        val zone = HuaweiPacketCrypto.WatchZone.fromPhone(now)
        syncedWatchZone = zone
        Log.i(
            TAG,
            "watch-zone push reason=$reason zoneId=${zone.zoneId} " +
                "offset=${zone.formatOffsetLabel()} phoneUnix=${zone.unixAtSync}",
        )
        val time = exchangeEncrypted(
            HuaweiFraming.Frame(SVC, CMD_SET_TIME, HuaweiPacketCrypto.timeAndZoneTlvs(now)),
            SVC,
            CMD_SET_TIME,
            CONFIGURE_TIMEOUT_MS,
        )
        if (time == null) {
            Log.w(TAG, "watch-zone set-time timeout reason=$reason")
        } else {
            recordWatchZoneFromSetTime(time, reason = reason, pushed = zone)
        }
        if (supportsCommand(SVC, CMD_TIME_ZONE_ID)) {
            val tz = exchangeEncrypted(
                HuaweiFraming.Frame(SVC, CMD_TIME_ZONE_ID, HuaweiPacketCrypto.timeZoneIdTlvs(now)),
                SVC,
                CMD_TIME_ZONE_ID,
                CONFIGURE_TIMEOUT_MS,
            )
            if (tz == null) {
                Log.w(TAG, "watch-zone timezone-id timeout reason=$reason")
            } else {
                recordWatchZoneFromTimezoneId(tz, reason = reason, pushed = zone)
            }
        }
    }

    private fun recordWatchZoneFromSetTime(
        response: HuaweiFraming.Frame,
        reason: String,
        pushed: HuaweiPacketCrypto.WatchZone = HuaweiPacketCrypto.WatchZone.fromPhone(),
    ) {
        syncedWatchZone = pushed
        val dump = HuaweiPacketCrypto.tlvTagDump(response)
        val deviceTime = HuaweiPacketCrypto.parseUnixTag(response, 0x01)
        val phoneUnix = pushed.unixAtSync
        val skewSec = if (deviceTime != null) deviceTime - phoneUnix else null
        lastWatchDeviceUnix = deviceTime
        lastWatchSkewSec = skewSec
        Log.i(
            TAG,
            "watch-zone set-time ok reason=$reason zoneId=${pushed.zoneId} " +
                "offset=${pushed.formatOffsetLabel()} phoneUnix=$phoneUnix " +
                "deviceUnix=$deviceTime skewSec=$skewSec tlvs=[$dump]",
        )
    }

    private fun recordWatchZoneFromTimezoneId(
        response: HuaweiFraming.Frame,
        reason: String,
        pushed: HuaweiPacketCrypto.WatchZone = syncedWatchZone,
    ) {
        syncedWatchZone = pushed
        val dump = HuaweiPacketCrypto.tlvTagDump(response)
        // If watch echoes IANA id, prefer it.
        val echoed = response.tlvs.firstOrNull { it.tag == 0x03 }?.value
            ?.toString(Charsets.UTF_8)
            ?.takeIf { it.isNotBlank() && it.length < 64 && !it.contains('\u0000') }
        if (echoed != null && echoed != pushed.zoneId) {
            syncedWatchZone = pushed.copy(zoneId = echoed)
            Log.i(
                TAG,
                "watch-zone timezone-id echoed reason=$reason echoed=$echoed " +
                    "(was ${pushed.zoneId}) tlvs=[$dump]",
            )
        } else {
            Log.i(
                TAG,
                "watch-zone timezone-id ok reason=$reason zoneId=${syncedWatchZone.zoneId} " +
                    "tlvs=[$dump]",
            )
        }
    }

    /** Write under `filesDir/vitals/sleep_files/{id}.bin`; return relative path. */
    private fun persistSleepFile(id: String, bytes: ByteArray): String? {
        val root = appFilesDir?.invoke() ?: return null
        val dir = java.io.File(root, "vitals/sleep_files")
        if (!dir.exists() && !dir.mkdirs()) {
            Log.w(TAG, "file-download mkdir failed ${dir.absolutePath}")
            return null
        }
        val safeId = id.replace(Regex("[^0-9A-Za-z._-]"), "_")
        if (safeId.isEmpty() || safeId != id) {
            Log.w(TAG, "file-download persist rejected id=$id")
            return null
        }
        val file = java.io.File(dir, "$safeId.bin")
        val canonicalDir = dir.canonicalFile
        val canonicalFile = file.canonicalFile
        if (!canonicalFile.path.startsWith(canonicalDir.path + java.io.File.separator) &&
            canonicalFile.path != canonicalDir.path
        ) {
            Log.w(TAG, "file-download persist path escape id=$safeId")
            return null
        }
        file.writeBytes(bytes)
        val rel = "vitals/sleep_files/$safeId.bin"
        Log.i(TAG, "file-download persisted id=$safeId len=${bytes.size} path=$rel")
        return rel
    }

    /**
     * Write under `filesDir/workouts/hr_samples/{id}.bin` (GateAPrefs.workoutHrSamplesDir).
     * Richer-file rule: empty / header-only must not replace a present series.
     */
    private fun persistWorkoutSampleFile(id: String, bytes: ByteArray): String? {
        val root = appFilesDir?.invoke() ?: return null
        val dir = java.io.File(root, HuaweiWorkoutSync.WORKOUT_HR_SAMPLES_DIR)
        if (!dir.exists() && !dir.mkdirs()) {
            Log.w(TAG, "workout-samples mkdir failed ${dir.absolutePath}")
            return null
        }
        val safeId = id.replace(Regex("[^0-9A-Za-z._-]"), "_")
        if (safeId.isEmpty() || safeId != id) {
            Log.w(TAG, "workout-samples persist rejected id=$id")
            return null
        }
        val file = java.io.File(dir, "$safeId.bin")
        val canonicalDir = dir.canonicalFile
        val canonicalFile = file.canonicalFile
        if (!canonicalFile.path.startsWith(canonicalDir.path + java.io.File.separator) &&
            canonicalFile.path != canonicalDir.path
        ) {
            Log.w(TAG, "workout-samples persist path escape id=$safeId")
            return null
        }
        val rel = "${HuaweiWorkoutSync.WORKOUT_HR_SAMPLES_DIR}/$safeId.bin"
        if (bytes.isEmpty()) {
            if (file.exists() && file.length() > 0) {
                Log.i(
                    TAG,
                    "workout-samples keep richer id=$safeId existingLen=${file.length()}",
                )
                return rel
            }
            Log.d(TAG, "workout-samples skip empty id=$safeId")
            return null
        }
        file.writeBytes(bytes)
        Log.i(TAG, "workout-samples persisted id=$safeId len=${bytes.size} path=$rel")
        return rel
    }

    /**
     * Write under `filesDir/workouts/leftovers/{id}.bin` (GateAPrefs.workoutLeftoversDir).
     * Peer to sample persist — used when MethodChannel leftover bodies would blow binder.
     */
    private fun persistWorkoutLeftoverFile(id: String, bytes: ByteArray): String? {
        val root = appFilesDir?.invoke() ?: return null
        val dir = java.io.File(root, HuaweiWorkoutSync.WORKOUT_LEFTOVERS_DIR)
        if (!dir.exists() && !dir.mkdirs()) {
            Log.w(TAG, "workout-leftovers mkdir failed ${dir.absolutePath}")
            return null
        }
        val safeId = id.replace(Regex("[^0-9A-Za-z._-]"), "_")
        if (safeId.isEmpty() || safeId != id) {
            Log.w(TAG, "workout-leftovers persist rejected id=$id")
            return null
        }
        val file = java.io.File(dir, "$safeId.bin")
        val canonicalDir = dir.canonicalFile
        val canonicalFile = file.canonicalFile
        if (!canonicalFile.path.startsWith(canonicalDir.path + java.io.File.separator) &&
            canonicalFile.path != canonicalDir.path
        ) {
            Log.w(TAG, "workout-leftovers persist path escape id=$safeId")
            return null
        }
        if (bytes.isEmpty()) {
            Log.d(TAG, "workout-leftovers skip empty id=$safeId")
            return null
        }
        file.writeBytes(bytes)
        val rel = "${HuaweiWorkoutSync.WORKOUT_LEFTOVERS_DIR}/$safeId.bin"
        Log.i(TAG, "workout-leftovers persisted id=$safeId len=${bytes.size} path=$rel")
        return rel
    }

    fun onRawBytes(bytes: ByteArray) {
        bytesReceived.addAndGet(bytes.size)
        Log.i(TAG, "session rx ${bytes.size}B total=${bytesReceived.get()} hex=${bytes.toHexFull()}")
        reassembly.write(bytes)
        drainBuffer()
    }

    private fun drainBuffer() {
        val buf = reassembly.toByteArray()
        var offset = 0
        while (offset < buf.size) {
            val slice = buf.copyOfRange(offset, buf.size)
            when (val result = HuaweiFraming.tryParse(slice)) {
                is HuaweiFraming.ParseResult.IncompleteFrame -> {
                    reassembly.reset()
                    reassembly.write(buf, offset, buf.size - offset)
                    return
                }
                is HuaweiFraming.ParseResult.Error -> {
                    Log.w(TAG, "frame error: ${result.reason} at+$offset")
                    offset += 1
                }
                is HuaweiFraming.ParseResult.Ok -> {
                    offset += result.bytesConsumed
                    val frame = result.frame
                    if (frame.isSliceFragment) handleSliceFragment(frame) else publishFrame(frame)
                }
            }
        }
        reassembly.reset()
    }

    private fun handleSliceFragment(frame: HuaweiFraming.Frame) {
        val payload = frame.slicePayload ?: return
        when (frame.flags) {
            HuaweiFraming.FLAG_SLICE_FIRST -> {
                assemblingSlices = true
                sliceAcc.reset()
                sliceAcc.write(payload)
            }
            HuaweiFraming.FLAG_SLICE_MIDDLE -> if (assemblingSlices) sliceAcc.write(payload)
            HuaweiFraming.FLAG_SLICE_LAST -> {
                if (!assemblingSlices) return
                sliceAcc.write(payload)
                val body = sliceAcc.toByteArray()
                assemblingSlices = false
                sliceAcc.reset()
                if (body.size >= 2) {
                    val svc = body[0].toInt() and 0xFF
                    val cmd = body[1].toInt() and 0xFF
                    val payload = body.copyOfRange(2, body.size)
                    val frame = if (
                        HuaweiFraming.isFileDownloadBlock(svc, cmd) &&
                        !(
                            payload.size >= 3 &&
                                (payload[0].toInt() and 0xFF) == 0x7C &&
                                (payload[1].toInt() and 0xFF) == 0x01 &&
                                (payload[2].toInt() and 0xFF) == 0x01
                            )
                    ) {
                        HuaweiFraming.Frame(
                            serviceId = svc,
                            commandId = cmd,
                            tlvs = emptyList(),
                            rawBody = payload,
                        )
                    } else {
                        HuaweiFraming.Frame(
                            serviceId = svc,
                            commandId = cmd,
                            tlvs = HuaweiFraming.decodeTlvs(payload),
                        )
                    }
                    publishFrame(frame)
                }
            }
        }
    }

    private fun publishFrame(frame: HuaweiFraming.Frame) {
        val key = sessionKey
        var decryptOk = true
        val isFileBlock = HuaweiFraming.isFileDownloadBlock(frame.serviceId, frame.commandId)
        val decrypted = if (key != null && encryptionEnabled && HuaweiPacketCrypto.isEncrypted(frame)) {
            if (isFileBlock) {
                try {
                    val plain = HuaweiPacketCrypto.decryptToBytes(frame, key, useGcm())
                    frame.copy(tlvs = emptyList(), rawBody = plain)
                } catch (e: Exception) {
                    val recovered = HuaweiPacketCrypto.decryptToBytesWithFallbacks(frame, key, useGcm())
                    if (recovered != null) {
                        Log.i(
                            TAG,
                            "file-download block decrypt recovered " +
                                "svc=0x${frame.serviceId.toString(16)} via=${recovered.second} " +
                                "len=${recovered.first.size}",
                        )
                        frame.copy(tlvs = emptyList(), rawBody = recovered.first)
                    } else {
                        Log.w(TAG, "file-download block decrypt failed: ${e.message}")
                        decryptOk = false
                        frame
                    }
                }
            } else {
                try {
                    HuaweiPacketCrypto.decryptIfNeeded(frame, key, useGcm())
                } catch (e: Exception) {
                    // Retry with trailing-null strip (GB TLV parser notes extra nulls) and
                    // AES-128 (first 16 of session key) before giving up.
                    val recovered = HuaweiPacketCrypto.decryptWithFallbacks(frame, key, useGcm())
                    if (recovered != null) {
                        Log.i(
                            TAG,
                            "session decrypt recovered svc=0x${frame.serviceId.toString(16)} " +
                                "cmd=0x${frame.commandId.toString(16)} via=${recovered.second}",
                        )
                        recovered.first
                    } else {
                        val ivLen = frame.tlvs.firstOrNull { it.tag == 0x7d }?.value?.size ?: -1
                        val ctLen = frame.tlvs.firstOrNull { it.tag == 0x7e }?.value?.size ?: -1
                        if (frame.serviceId == SVC_MUSIC) {
                            Log.w(
                                TAG,
                                "music decrypt failed (gcm/cbc): ${e.message} ivLen=$ivLen ctLen=$ctLen keyLen=${key.size}",
                            )
                        } else {
                            Log.w(
                                TAG,
                                "session decrypt failed svc=0x${frame.serviceId.toString(16)} " +
                                    "cmd=0x${frame.commandId.toString(16)}: ${e.message} " +
                                    "ivLen=$ivLen ctLen=$ctLen keyLen=${key.size}",
                            )
                        }
                        decryptOk = false
                        frame
                    }
                }
            }
        } else {
            frame
        }
        if (isFileBlock) {
            Log.d(
                TAG,
                "file-download block rx svc=0x${decrypted.serviceId.toString(16)} " +
                    "rawLen=${decrypted.rawBody?.size ?: 0}",
            )
        } else {
            logTlvs(decrypted)
        }

        // Async handlers must run in publishFrame — awaitFrame drops unrelated frames
        // while waiting for configure responses.
        if (encryptionEnabled && decryptOk) {
            maybeRespondPhoneInfo(decrypted)
            // DataSync (svc=0x37): selective — featureManager action=2 starts file upload.
            // Bare t=7f OK on all cmds poisoned the session after music-params OK.
            maybeHandleDataSync(decrypted)
            if (productSyncActive) {
                if (decrypted.serviceId == HuaweiFeatureUpload.SVC_FILE) {
                    Log.d(TAG, "feature-upload hard-off during product sync — ignore 0x28")
                }
            } else {
                featureUpload.onFileUploadFrame(decrypted)
            }
            maybeAckP2P(decrypted)
            maybeAckMusicAsync(decrypted)
            maybeEmitLiftSvc02Frame(decrypted)
            maybeHandleNotificationReply(decrypted, decryptOk)
            maybeHandleLiftP2PInbound(decrypted)
        }

        synchronized(frameLock) {
            frameQueue.addLast(decrypted)
        }
        inbound.get()?.countDown()
        emit(
            mapOf(
                "type" to "session_frame",
                "serviceId" to decrypted.serviceId,
                "commandId" to decrypted.commandId,
            ),
        )
    }

    fun authenticate(): SessionOutcome {
        Log.i(TAG, "authenticate() start hasSecrets=${secrets.hasSecrets()}")
        HuaweiSyncBreadcrumbs.authStep("authenticate_start", true)
        emit(mapOf("type" to "session_state", "state" to "authenticating"))
        return try {
            bytesReceived.set(0)
            reassembly.reset()
            sliceAcc.reset()
            assemblingSlices = false
            sessionKey = null
            encryptionEnabled = false
            encryptionCounter.set(0)
            expandCapabilities = null
            commandsByService = emptyMap()
            accountConfigureDone = false
            pendingFeatureManagerAction2 = false
            featureUpload.reset()
            synchronized(frameLock) { frameQueue.clear() }
            awaitAnyFrame(LISTEN_BEFORE_SEND_MS)

            HuaweiSyncBreadcrumbs.authStep("link_params_request", true)
            val linkResp = exchange(
                HuaweiFraming.Frame(
                    SVC, CMD_LINK_PARAMS,
                    listOf(
                        HuaweiFraming.Tlv(0x01, byteArrayOf()),
                        HuaweiFraming.Tlv(0x02, byteArrayOf()),
                        HuaweiFraming.Tlv(0x03, byteArrayOf()),
                        HuaweiFraming.Tlv(0x04, byteArrayOf()),
                    ),
                ),
                CMD_LINK_PARAMS,
            ) ?: return failAndDisconnect("No link-params response", "r11_retry")

            HuaweiSyncBreadcrumbs.authStep("link_params_response", true)
            val link = parseLinkParams(linkResp)
                ?: return failAndDisconnect("Could not parse link-params", "r11_hci_capture_needed")
            sliceSize = link.maxFrameSize.takeIf { it > 64 } ?: 0x00F4
            Log.i(
                TAG,
                "link-params ok authVersion=${link.authVersion.code} " +
                    "supportType=${link.deviceSupportType}(${supportTypeLabel(link.deviceSupportType)}) " +
                    "sliceSize=$sliceSize serverNonce=${link.serverNonce.toHexFull()}",
            )

            val statusResp = exchange(
                HuaweiFraming.Frame(SVC, CMD_DEVICE_STATUS, listOf(HuaweiFraming.Tlv(0x01, byteArrayOf()))),
                CMD_DEVICE_STATUS,
            )
            Log.i(
                TAG,
                "device-status ok status=${statusResp?.tlvs?.firstOrNull { it.tag == 0x01 }?.value?.firstOrNull()?.toInt()?.and(0xFF)}",
            )

            val result = if (isHiChainFamily(link.deviceSupportType)) runHiChain3(link) else runNormalAuth(link)
            HuaweiSyncBreadcrumbs.authStep(
                "authenticate_complete",
                result == SessionOutcome.Ready
            )
            result
        } catch (e: Exception) {
            Log.e(TAG, "authenticate failed", e)
            HuaweiSyncBreadcrumbs.authStep("authenticate_exception", false)
            HuaweiSyncBreadcrumbs.captureException(
                e,
                "authenticate",
                mapOf("hasSecrets" to secrets.hasSecrets())
            )
            failAndDisconnect(e.message ?: "authenticate failed", "r11_retry")
        }
    }

    private fun runHiChain3(link: LinkParams): SessionOutcome {
        val authMode = if (link.deviceSupportType == 4) 4 else 2
        val androidId = secrets.getOrCreateAndroidIdToken()
        emit(
            mapOf(
                "type" to "session_state",
                "state" to "authenticating",
                "message" to "HiChain3 — confirm pairing on the watch if prompted",
                "hint" to "r11_confirm_on_watch",
            ),
        )

        val negoTlvs = mutableListOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(authMode.toByte())),
            HuaweiFraming.Tlv(0x02, byteArrayOf(0x01)),
            HuaweiFraming.Tlv(0x05, androidId.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x03, byteArrayOf(0x01)),
            HuaweiFraming.Tlv(0x04, byteArrayOf(0x00)),
        )
        if (authMode == 4) {
            negoTlvs += HuaweiFraming.Tlv(0x06, byteArrayOf())
            negoTlvs += HuaweiFraming.Tlv(0x07, android.os.Build.MODEL.toByteArray(Charsets.UTF_8))
        }
        exchange(HuaweiFraming.Frame(SVC, CMD_SECURITY_NEGO, negoTlvs), CMD_SECURITY_NEGO)
            ?: return failAndDisconnect("No security-nego response", "r11_hichain3_required")
        Log.i(TAG, "security-nego ok")

        val pinResp = exchange(
            HuaweiFraming.Frame(SVC, HuaweiHiChain.CMD_PIN, listOf(HuaweiFraming.Tlv(0x01, byteArrayOf()))),
            HuaweiHiChain.CMD_PIN,
            timeoutMs = HICHAIN_STEP_TIMEOUT_MS,
        ) ?: return failAndDisconnect(
            "No PIN response — look at the watch and accept pairing, then retry",
            "r11_confirm_on_watch",
        )
        val pinCipher = pinResp.tlvs.firstOrNull { it.tag == 0x01 }?.value
            ?: return failAndDisconnect("PIN missing ciphertext", "r11_hichain3_required")
        val pinIv = pinResp.tlvs.firstOrNull { it.tag == 0x02 }?.value
            ?: return failAndDisconnect("PIN missing IV", "r11_hichain3_required")
        val pinBytes = try {
            HuaweiHiChain.decryptPin(pinCipher, pinIv, link.authVersion, link.encryptMethod)
        } catch (e: Exception) {
            return failAndDisconnect("PIN decrypt failed: ${e.message}", "r11_hichain3_required")
        }
        Log.i(TAG, "PIN ok (${pinBytes.size}B) — HiChain auth; confirm on watch if asked")

        val selfAuthId = androidId.toByteArray(Charsets.UTF_8)
        val authKey = runHiChainOperation(0x01, selfAuthId, pinBytes, null)
            ?: return failAndDisconnect(
                "HiChain authenticate failed — accept on watch within ~30s and retry",
                "r11_confirm_on_watch",
            )
        val bindKey = runHiChainOperation(0x02, selfAuthId, null, authKey)
            ?: return failAndDisconnect("HiChain bind failed", "r11_hichain3_required")

        enableSessionCrypto(bindKey, link)
        secrets.setAuthMaterial(bindKey.toHexFull())
        if (!runPostBindConfigure()) {
            return failAndDisconnect(
                "Post-bind configure failed — watch may still show pairing failed",
                "r11_retry",
            )
        }
        Log.i(TAG, "authenticate → Ready (HiChain3 bind + configure)")
        emit(mapOf("type" to "session_state", "state" to "session_ready"))
        return SessionOutcome.Ready
    }

    private fun runHiChainOperation(
        operationCode: Int,
        selfAuthId: ByteArray,
        pinBytes: ByteArray?,
        existingSecret: ByteArray?,
    ): ByteArray? {
        val requestId = System.currentTimeMillis()
        val seed = HuaweiHiChain.random(32)
        val randSelf = HuaweiHiChain.random(16)

        writeHiChain(HuaweiHiChain.buildStepOne(operationCode, requestId, selfAuthId, randSelf, seed))
        val step1Frame = awaitFrame(SVC, HuaweiHiChain.CMD, HICHAIN_STEP_TIMEOUT_MS) ?: return null
        val step1 = HuaweiHiChain.parsePeerStep(step1Frame) as? HuaweiHiChain.PeerStep.Step1 ?: return null
        val randPeer = step1.data.isoSalt
        val authIdPeer = step1.data.peerAuthId
        val psk = if (operationCode == 0x01) {
            HuaweiHiChain.pskFromPin(pinBytes!!, seed)
        } else {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(existingSecret!!, "HmacSHA256"))
            mac.doFinal(seed)
        }
        if (!HuaweiHiChain.verifyPeerToken(psk, randPeer, randSelf, selfAuthId, authIdPeer, step1.data.token)) {
            Log.w(TAG, "HiChain peer token mismatch")
            return null
        }
        Log.i(TAG, "HiChain op=$operationCode step1 ok")

        val token = HuaweiHiChain.selfToken(psk, randSelf, randPeer, selfAuthId, authIdPeer)
        writeHiChain(HuaweiHiChain.buildStepTwo(operationCode, requestId, selfAuthId, token))
        val step2Frame = awaitFrame(SVC, HuaweiHiChain.CMD, HICHAIN_STEP_TIMEOUT_MS) ?: return null
        val step2 = HuaweiHiChain.parsePeerStep(step2Frame) as? HuaweiHiChain.PeerStep.Step2 ?: return null
        if (!HuaweiHiChain.verifyReturnCodeMac(psk, step2.returnCodeMac)) {
            Log.w(TAG, "HiChain returnCodeMac mismatch")
            return null
        }
        Log.i(TAG, "HiChain op=$operationCode step2 ok")

        val sessionKey = HuaweiHiChain.sessionKey(psk, randSelf, randPeer)
        if (operationCode == 0x01) {
            val nonce = HuaweiHiChain.random(12)
            val challenge = HuaweiHiChain.random(16)
            val enc = HuaweiHiChain.encryptExchangeChallenge(sessionKey, challenge, nonce)
            writeHiChain(HuaweiHiChain.buildStepThree(operationCode, requestId, selfAuthId, nonce, enc))
            val step3Frame = awaitFrame(SVC, HuaweiHiChain.CMD, HICHAIN_STEP_TIMEOUT_MS) ?: return null
            val step3 = HuaweiHiChain.parsePeerStep(step3Frame) as? HuaweiHiChain.PeerStep.Step3 ?: return null
            val authToken = HuaweiHiChain.decryptAuthToken(sessionKey, step3.encAuthToken, step3.nonce, challenge)
            val nonce4 = HuaweiHiChain.random(12)
            writeHiChain(
                HuaweiHiChain.buildStepFour(
                    operationCode, requestId, selfAuthId, nonce4,
                    HuaweiHiChain.encryptResult(sessionKey, nonce4),
                    messageStep = 4,
                ),
            )
            awaitFrame(SVC, HuaweiHiChain.CMD, HICHAIN_STEP_TIMEOUT_MS) ?: return null
            Log.i(TAG, "HiChain authenticate complete")
            return authToken
        }

        // Bind: result packet is built when internal step is still 3 → message 0x13.
        val nonce4 = HuaweiHiChain.random(12)
        writeHiChain(
            HuaweiHiChain.buildStepFour(
                operationCode, requestId, selfAuthId, nonce4,
                HuaweiHiChain.encryptResult(sessionKey, nonce4),
                messageStep = 3,
            ),
        )
        awaitFrame(SVC, HuaweiHiChain.CMD, HICHAIN_STEP_TIMEOUT_MS) ?: return null
        val key = HuaweiHiChain.returnKey(sessionKey, randSelf, randPeer)
        Log.i(TAG, "HiChain bind complete")
        return key
    }

    private fun writeHiChain(packet: HuaweiHiChain.BuiltPacket) {
        synchronized(frameLock) { frameQueue.clear() }
        val parts = HuaweiFraming.encodePossiblySliced(SVC, HuaweiHiChain.CMD, packet.tlvs, sliceSize)
        for (part in parts) {
            Log.i(TAG, "tx HiChain ${part.size}B")
            transport.write(part)
        }
    }

    private fun runNormalAuth(link: LinkParams): SessionOutcome {
        val clientNonce = HuaweiNormalAuth.generateNonce()
        val deviceMac = transport.remoteMac ?: return failAndDisconnect("Missing remote MAC", "r11_retry")
        val clientMac = secrets.getPhoneMac() ?: transport.localBluetoothAddress()
            ?: return failAndDisconnect("Phone BT MAC unavailable", "r11_phone_mac")
        val clientSerial = clientMac.replace(":", "").takeLast(6)

        val authResp = exchange(
            HuaweiFraming.Frame(
                SVC, CMD_AUTH,
                listOf(
                    HuaweiFraming.Tlv(0x01, HuaweiNormalAuth.digestChallenge(link.authVersion, clientNonce, link.serverNonce)),
                    HuaweiFraming.Tlv(
                        0x02,
                        byteArrayOf(
                            ((link.authVersion.code shr 8) and 0xFF).toByte(),
                            (link.authVersion.code and 0xFF).toByte(),
                        ) + clientNonce,
                    ),
                ),
            ),
            CMD_AUTH,
        ) ?: return failAndDisconnect("No auth response", "r11_retry_or_account_id")

        val authResult = resultCode(authResp)
        if (authResult != null && authResult != RESULT_SUCCESS) {
            return failAndDisconnect("Auth rejected ($authResult)", "r11_factory_reset_or_account_id")
        }
        if (!verifyAuthResponse(link.authVersion, authResp, clientNonce, link.serverNonce)) {
            return failAndDisconnect("Auth digest mismatch", "r11_account_id_or_factory_reset")
        }

        exchange(
            HuaweiFraming.Frame(
                SVC, CMD_BOND_PARAMS,
                listOf(
                    HuaweiFraming.Tlv(0x01, byteArrayOf()),
                    HuaweiFraming.Tlv(0x03, clientSerial.toByteArray(Charsets.US_ASCII)),
                    HuaweiFraming.Tlv(0x04, byteArrayOf(0x02)),
                    HuaweiFraming.Tlv(0x05, byteArrayOf()),
                    HuaweiFraming.Tlv(0x07, clientMac.toByteArray(Charsets.US_ASCII)),
                    HuaweiFraming.Tlv(0x09, byteArrayOf()),
                ),
            ),
            CMD_BOND_PARAMS,
        ) ?: return failAndDisconnect("No bond-params", "r11_retry")

        val masterKey = HuaweiNormalAuth.generateNonce()
        val iv = HuaweiNormalAuth.generateNonce()
        exchange(
            HuaweiFraming.Frame(
                SVC, CMD_BOND,
                listOf(
                    HuaweiFraming.Tlv(0x01, byteArrayOf()),
                    HuaweiFraming.Tlv(0x03, byteArrayOf(0x00)),
                    HuaweiFraming.Tlv(0x05, clientSerial.toByteArray(Charsets.US_ASCII)),
                    HuaweiFraming.Tlv(0x06, HuaweiNormalAuth.createBondingKey(link.authVersion, deviceMac, masterKey, iv)),
                    HuaweiFraming.Tlv(0x07, iv),
                ),
            ),
            CMD_BOND,
        ) ?: return failAndDisconnect("No bond response", "r11_retry")

        enableSessionCrypto(masterKey, link)
        secrets.setAuthMaterial(masterKey.toHexFull())
        if (!runPostBindConfigure()) {
            return failAndDisconnect(
                "Post-bind configure failed — watch may still show pairing failed",
                "r11_retry",
            )
        }
        emit(mapOf("type" to "session_state", "state" to "session_ready"))
        return SessionOutcome.Ready
    }

    private fun enableSessionCrypto(key: ByteArray, link: LinkParams) {
        sessionKey = key
        deviceSupportType = link.deviceSupportType
        encryptMethod = link.encryptMethod
        encryptionEnabled = true
        encryptionCounter.set(0)
        Log.i(
            TAG,
            "session crypto on keyLen=${key.size} gcm=${useGcm()} supportType=${link.deviceSupportType}",
        )
    }

    private fun useGcm(): Boolean =
        HuaweiPacketCrypto.useGcm(deviceSupportType, encryptMethod)

    /**
     * After HiChain/Normal auth the watch still expects an encrypted configure
     * handshake. Stopping at set-time leaves the watch UI on "pairing failed"
     * after a timeout — GB continues with battery + supported-services.
     */
    private fun runPostBindConfigure(): Boolean {
        Log.i(TAG, "post-bind configure start")
        val productTags = PRODUCT_INFO_TAGS.map { HuaweiFraming.Tlv(it, byteArrayOf()) }
        val product = exchangeEncrypted(
            HuaweiFraming.Frame(SVC, CMD_PRODUCT_INFO, productTags),
            SVC,
            CMD_PRODUCT_INFO,
            CONFIGURE_TIMEOUT_MS,
        )
        if (product == null) {
            Log.w(TAG, "post-bind: no product-info response")
            return false
        }
        Log.i(TAG, "post-bind: product-info ok")

        val time = exchangeEncrypted(
            HuaweiFraming.Frame(SVC, CMD_SET_TIME, HuaweiPacketCrypto.timeAndZoneTlvs()),
            SVC,
            CMD_SET_TIME,
            CONFIGURE_TIMEOUT_MS,
        )
        if (time == null) {
            Log.w(TAG, "post-bind: no set-time response")
            return false
        }
        recordWatchZoneFromSetTime(time, reason = "post-bind")

        // Battery may time out on some firmware; GB continues either way.
        val battery = exchangeEncrypted(
            HuaweiFraming.Frame(SVC, CMD_BATTERY, listOf(HuaweiFraming.Tlv(0x01, byteArrayOf()))),
            SVC,
            CMD_BATTERY,
            CONFIGURE_TIMEOUT_MS,
        )
        if (battery == null) {
            Log.w(TAG, "post-bind: no battery response — continuing")
        } else {
            val level = battery.tlvs.firstOrNull { it.tag == 0x01 }?.value?.firstOrNull()?.toInt()?.and(0xFF)
            Log.i(TAG, "post-bind: battery ok level=$level")
        }

        val services = exchangeEncrypted(
            HuaweiFraming.Frame(
                SVC,
                CMD_SUPPORTED_SERVICES,
                listOf(HuaweiFraming.Tlv(0x01, KNOWN_SUPPORTED_SERVICES)),
            ),
            SVC,
            CMD_SUPPORTED_SERVICES,
            CONFIGURE_TIMEOUT_MS,
        )
        if (services == null) {
            Log.w(TAG, "post-bind: no supported-services response")
            return false
        }
        val activeMask = services.tlvs.firstOrNull { it.tag == 0x02 }?.value
        val activeIds = parseActiveServiceIds(activeMask)
        Log.i(
            TAG,
            "post-bind: supported-services ok maskLen=${activeMask?.size ?: 0} " +
                "active=${activeIds.joinToString(",") { "0x${it.toString(16)}" }}",
        )

        // GB: SupportedServices → SupportedCommands (batched) → Expand → dynamic init.
        commandsByService = runSupportedCommands(activeIds)
        Log.i(
            TAG,
            "post-bind: supported-commands ok services=${commandsByService.size} " +
                "acct05=${supportsCommand(SVC_ACCOUNT, CMD_EXTENDED_ACCOUNT)} " +
                "acct06=${supportsCommand(SVC_ACCOUNT, CMD_ACCOUNT_SWITCH)} " +
                "setting31=${supportsCommand(SVC, CMD_SETTING_RELATED)} " +
                "rev3f=${supportsCommand(SVC, CMD_REVERSE_CAPABILITIES)}",
        )

        // Timezone id (0x32) — GB sends during dynamic init when supported.
        if (activeIds.contains(CMD_TIME_ZONE_ID) || supportsCommand(SVC, CMD_TIME_ZONE_ID)) {
            val tz = exchangeEncrypted(
                HuaweiFraming.Frame(SVC, CMD_TIME_ZONE_ID, HuaweiPacketCrypto.timeZoneIdTlvs()),
                SVC,
                CMD_TIME_ZONE_ID,
                CONFIGURE_TIMEOUT_MS,
            )
            if (tz == null) {
                Log.w(TAG, "post-bind: no timezone-id response — continuing")
            } else {
                recordWatchZoneFromTimezoneId(tz, reason = "post-bind")
            }
        }

        // ExpandCapability (DeviceConfig cmd 0x37).
        run {
            val expand = exchangeEncrypted(
                HuaweiFraming.Frame(SVC, CMD_EXPAND_CAPABILITY, listOf(HuaweiFraming.Tlv(0x01, byteArrayOf()))),
                SVC,
                CMD_EXPAND_CAPABILITY,
                CONFIGURE_TIMEOUT_MS,
            )
            if (expand == null) {
                Log.w(TAG, "post-bind: no expand-capability response — continuing")
            } else {
                expandCapabilities = expand.tlvs.firstOrNull { it.tag == 0x01 }?.value
                val capLen = expandCapabilities?.size ?: 0
                Log.i(TAG, "post-bind: expand-capability ok bytes=$capLen")
            }
        }

        // GB dynamic init: ExtendedAccount → SettingRelated → … Country late.
        runExtendedAccount(activeIds)
        runSettingRelated()
        accountConfigureDone = true
        flushPendingFeatureManagerUpload()

        // Locale (0x0C) is active on this GT5.
        if (activeIds.contains(SVC_LOCALE) || supportsCommand(SVC_LOCALE, CMD_SET_LANGUAGE)) {
            val locale = java.util.Locale.getDefault()
            val country = locale.country.ifBlank { locale.language }.uppercase()
            val localeStr = "${locale.language}-$country"
            val lang = exchangeEncrypted(
                HuaweiFraming.Frame(
                    SVC_LOCALE,
                    CMD_SET_LANGUAGE,
                    listOf(
                        HuaweiFraming.Tlv(0x01, localeStr.toByteArray(Charsets.UTF_8)),
                        HuaweiFraming.Tlv(0x02, byteArrayOf(MEASUREMENT_METRIC)),
                    ),
                ),
                SVC_LOCALE,
                CMD_SET_LANGUAGE,
                CONFIGURE_TIMEOUT_MS,
            )
            if (lang == null) {
                Log.w(TAG, "post-bind: no set-language response — continuing")
            } else {
                Log.i(TAG, "post-bind: set-language ok locale=$localeStr")
            }
        }

        // Date/time format (DeviceConfig 0x04).
        run {
            val nested = HuaweiFraming.encodeTlvs(
                listOf(
                    HuaweiFraming.Tlv(0x02, byteArrayOf(DATE_YEAR_FIRST.toByte())),
                    HuaweiFraming.Tlv(0x03, byteArrayOf(TIME_HOURS_24.toByte())),
                ),
            )
            val df = exchangeEncrypted(
                HuaweiFraming.Frame(SVC, CMD_DATE_FORMAT, listOf(HuaweiFraming.Tlv(0x81, nested))),
                SVC,
                CMD_DATE_FORMAT,
                CONFIGURE_TIMEOUT_MS,
            )
            if (df == null) {
                Log.w(TAG, "post-bind: no date-format response — continuing")
            } else {
                Log.i(TAG, "post-bind: date-format ok")
            }
        }

        // Watch often does not answer setup-device-status; send fire-and-forget.
        val setupName = transport.remoteName?.takeIf { it.isNotBlank() } ?: "HUAWEI WATCH GT 5"
        sendEncryptedNoWait(
            HuaweiFraming.Frame(
                SVC,
                CMD_SETUP_DEVICE_STATUS,
                listOf(
                    HuaweiFraming.Tlv(0x01, byteArrayOf(0x01)), // relationship = main
                    HuaweiFraming.Tlv(0x02, setupName.toByteArray(Charsets.UTF_8)),
                    HuaweiFraming.Tlv(0x03, byteArrayOf(0x00)),
                ),
            ),
        )
        Log.i(TAG, "post-bind: setup-device-status sent name=$setupName")

        // GT5 mask includes 0x30 — GB AcceptAgreements during dynamic init.
        if (activeIds.contains(0x30) || supportsCommand(SVC, CMD_ACCEPT_AGREEMENT)) {
            val agreement = exchangeEncrypted(
                HuaweiFraming.Frame(SVC, CMD_ACCEPT_AGREEMENT, buildAcceptAgreementTlvs()),
                SVC,
                CMD_ACCEPT_AGREEMENT,
                CONFIGURE_TIMEOUT_MS,
            )
            if (agreement == null) {
                Log.w(TAG, "post-bind: no accept-agreement response — continuing")
            } else {
                Log.i(TAG, "post-bind: accept-agreement ok")
            }
        }

        // Master GB: ReverseCapabilities right after AcceptAgreements.
        runReverseCapabilities()

        // Connect-status (0x35) — mark link up.
        if (activeIds.contains(0x35) || supportsCommand(SVC, CMD_CONNECT_STATUS)) {
            val status = exchangeEncrypted(
                HuaweiFraming.Frame(
                    SVC,
                    CMD_CONNECT_STATUS,
                    listOf(HuaweiFraming.Tlv(0x01, byteArrayOf(0x01))),
                ),
                SVC,
                CMD_CONNECT_STATUS,
                CONFIGURE_TIMEOUT_MS,
            )
            if (status == null) {
                Log.w(TAG, "post-bind: no connect-status response — continuing")
            } else {
                Log.i(TAG, "post-bind: connect-status ok")
            }
        }

        if (activeIds.contains(SVC_MUSIC) || supportsCommand(SVC_MUSIC, CMD_MUSIC_INFO_PARAMS)) {
            runMusicCapabilityProbes()
        }

        // Master GB sends Country Code late in dynamic init (after music/locale).
        runCountryCode(activeIds)

        Log.i(TAG, "post-bind: configure complete")
        return true
    }

    /**
     * GB `GetMusicInfoParams` (0x25:0x04) + `GetExtendedMusicInfoParams` (0x25:0x0D).
     * Empty-tag probes only — behavioral oracle from public MusicControl packet shape.
     */
    private fun runMusicCapabilityProbes() {
        val infoTags = listOf(0x01, 0x02, 0x03).map { HuaweiFraming.Tlv(it, byteArrayOf()) }
        val info = exchangeEncrypted(
            HuaweiFraming.Frame(SVC_MUSIC, CMD_MUSIC_INFO_PARAMS, infoTags),
            SVC_MUSIC,
            CMD_MUSIC_INFO_PARAMS,
            CONFIGURE_TIMEOUT_MS,
        )
        if (info == null) {
            Log.w(TAG, "post-bind: no music-info-params response — continuing")
        } else {
            Log.i(TAG, "post-bind: music-info-params ok tags=${info.tlvs.size}")
        }

        val extTags = listOf(0x01, 0x02, 0x03, 0x04, 0x05).map { HuaweiFraming.Tlv(it, byteArrayOf()) }
        val ext = exchangeEncrypted(
            HuaweiFraming.Frame(SVC_MUSIC, CMD_MUSIC_EXTENDED_PARAMS, extTags),
            SVC_MUSIC,
            CMD_MUSIC_EXTENDED_PARAMS,
            CONFIGURE_TIMEOUT_MS,
        )
        if (ext == null) {
            Log.w(TAG, "post-bind: no music-extended-params response — continuing")
        } else {
            Log.i(TAG, "post-bind: music-extended-params ok tags=${ext.tlvs.size}")
        }
    }

    /** Map supported-services bitmask (tag 0x02) onto [KNOWN_SUPPORTED_SERVICES] ids. */
    private fun parseActiveServiceIds(mask: ByteArray?): Set<Int> {
        if (mask == null) return emptySet()
        val out = HashSet<Int>()
        val n = minOf(mask.size, KNOWN_SUPPORTED_SERVICES.size)
        for (i in 0 until n) {
            if (mask[i].toInt() and 0xFF == 1) {
                out.add(KNOWN_SUPPORTED_SERVICES[i].toInt() and 0xFF)
            }
        }
        return out
    }

    /**
     * Nested AcceptAgreement payload (cmd 0x30) — three statements under 0x81/0x82.
     * Wire shape from public LPv2 / GB behavioral oracle (not AGPL paste).
     */
    private fun buildAcceptAgreementTlvs(): List<HuaweiFraming.Tlv> {
        val ts = (System.currentTimeMillis() / 1000L).toInt()
        fun agreement(name: String): HuaweiFraming.Tlv {
            val inner = HuaweiFraming.encodeTlvs(
                listOf(
                    HuaweiFraming.Tlv(0x03, name.toByteArray(Charsets.UTF_8)),
                    HuaweiFraming.Tlv(0x04, HuaweiPacketCrypto.intBe(1)),
                    HuaweiFraming.Tlv(0x05, "20230508-20230508-0-0".toByteArray(Charsets.UTF_8)),
                    HuaweiFraming.Tlv(0x06, HuaweiPacketCrypto.intBe(ts)),
                ),
            )
            return HuaweiFraming.Tlv(0x82, inner)
        }
        val list = HuaweiFraming.encodeTlvs(
            listOf(
                agreement("software_update_service_statement"),
                agreement("device_information_management"),
                agreement("user_license_agreement"),
            ),
        )
        return listOf(HuaweiFraming.Tlv(0x81, list))
    }

    /**
     * Async PhoneInfo (`1:0x10`): watch sends empty-tag probes listing fields it wants;
     * phone must reply with values. Matches GB AsynchronousResponse.handlePhoneInfo.
     */
    private fun maybeRespondPhoneInfo(frame: HuaweiFraming.Frame) {
        if (frame.serviceId != SVC || frame.commandId != CMD_PHONE_INFO) return
        // Watch ack of our prior reply — do not echo.
        if (frame.tlvs.size == 1 && frame.tlvs[0].tag == TAG_RESULT) {
            val code = frame.tlvs[0].value
            if (code.size == 4) {
                val v = ((code[0].toInt() and 0xFF) shl 24) or
                    ((code[1].toInt() and 0xFF) shl 16) or
                    ((code[2].toInt() and 0xFF) shl 8) or
                    (code[3].toInt() and 0xFF)
                if (v == HuaweiPacketCrypto.RESULT_OK || v == RESULT_SUCCESS) {
                    Log.d(TAG, "phone-info ack ignored")
                    return
                }
            }
        }
        val requested = frame.tlvs.map { it.tag }
        if (requested.isEmpty()) return
        val reply = buildPhoneInfoTlvs(requested)
        if (reply.isEmpty()) {
            Log.w(TAG, "phone-info: nothing to reply for tags=$requested")
            return
        }
        Log.i(TAG, "tx phone-info reply for tags=${requested.joinToString(",") { "0x${it.toString(16)}" }}")
        sendEncryptedNoWait(HuaweiFraming.Frame(SVC, CMD_PHONE_INFO, reply))
    }

    /**
     * Async DataSync (`svc=0x37`) — GB AsynchronousResponse → HuaweiDataSyncManager.
     *
     * Retest evidence: music-info/extended probes decrypted OK with the session key;
     * immediately after our bare `t=7f:100000` reply to `featureManager` configAction=2,
     * Music/`0x37` GCM MAC failed and the watch closed RFCOMM. So blanket OK is wrong.
     *
     * GB FeatureManager (behavioral): for configAction=2 send ConfigCommand
     * src=`hw.unitedevice.configManager` → dst=`featureManager` with
     * configId=900100007, action=2, data=`"01"` — **no** `t=7f`. (File upload of the
     * features JSON is a follow-on; Gate A first restores the correct handshake.)
     */
    private fun maybeHandleDataSync(frame: HuaweiFraming.Frame) {
        if (frame.serviceId != SVC_DATASYNC) return
        if (frame.tlvs.any { it.tag == TAG_RESULT }) return

        val src = frame.tlvs.firstOrNull { it.tag == TAG_DATASYNC_SRC }?.value
            ?.toString(Charsets.UTF_8)
            ?: return
        val dst = frame.tlvs.firstOrNull { it.tag == TAG_DATASYNC_DST }?.value
            ?.toString(Charsets.UTF_8)
            ?: return

        when (frame.commandId) {
            CMD_DATASYNC_CONFIG -> {
                if (src != PKG_FEATURE_MANAGER) {
                    Log.d(TAG, "datasync config ignore src=$src dst=$dst")
                    return
                }
                val action = parseDataSyncConfigAction(frame) ?: run {
                    Log.d(TAG, "datasync featureManager: no configAction — ignore")
                    return
                }
                if (action != FEATURE_CONFIG_ACTION_REQUEST) {
                    Log.d(TAG, "datasync featureManager action=$action — ignore")
                    return
                }
                if (!accountConfigureDone) {
                    Log.i(
                        TAG,
                        "datasync featureManager action=2 — defer until Extended Account/country",
                    )
                    pendingFeatureManagerAction2 = true
                    return
                }
                startFeatureManagerUpload()
            }
            else -> {
                // Event/data/dict: GB module handlers rarely send bare OK; skip.
                Log.d(
                    TAG,
                    "datasync ignore cmd=0x${frame.commandId.toString(16)} src=$src dst=$dst",
                )
            }
        }
    }

    /** First configAction byte under nested `t=83` / `t=84` / `t=6`. */
    private fun parseDataSyncConfigAction(frame: HuaweiFraming.Frame): Int? {
        val listBytes = frame.tlvs.firstOrNull { it.tag == TAG_DATASYNC_CONFIG_LIST }?.value
            ?: return null
        val items = try {
            HuaweiFraming.decodeTlvs(listBytes)
        } catch (_: Exception) {
            return null
        }
        for (item in items) {
            if (item.tag != TAG_DATASYNC_CONFIG_ITEM) continue
            val fields = try {
                HuaweiFraming.decodeTlvs(item.value)
            } catch (_: Exception) {
                continue
            }
            val action = fields.firstOrNull { it.tag == TAG_DATASYNC_CONFIG_ACTION }
                ?.value
                ?.lastOrNull()
                ?.toInt()
                ?.and(0xFF)
            if (action != null) return action
        }
        return null
    }

    /**
     * GB SupportedCommands (`0x01:0x03`): batch active services into ≤~slice-sized
     * probes (command does not support slicing). Nested `t=81` of `t=2`/`t=3` pairs.
     */
    private fun runSupportedCommands(activeIds: Set<Int>): Map<Int, Set<Int>> {
        val remaining = ArrayDeque(activeIds.sorted())
        val out = LinkedHashMap<Int, MutableSet<Int>>()
        if (remaining.isEmpty()) return out

        var maxPlain = (sliceSize - 32).coerceAtLeast(64)
        maxPlain = maxPlain - (maxPlain % 16) - 4

        while (remaining.isNotEmpty()) {
            val batch = ArrayList<HuaweiFraming.Tlv>()
            var size = 0
            while (remaining.isNotEmpty()) {
                val svc = remaining.first()
                val cmds = activeCommandsProbe()[svc] ?: byteArrayOf(0x01)
                val addLen = cmds.size + 5
                if (batch.isNotEmpty() && size + addLen > maxPlain) break
                remaining.removeFirst()
                batch += HuaweiFraming.Tlv(0x02, byteArrayOf(svc.toByte()))
                batch += HuaweiFraming.Tlv(0x03, cmds)
                size += addLen
            }
            val nested = HuaweiFraming.encodeTlvs(batch)
            val resp = exchangeEncrypted(
                HuaweiFraming.Frame(
                    SVC,
                    CMD_SUPPORTED_COMMANDS,
                    listOf(HuaweiFraming.Tlv(0x81, nested)),
                ),
                SVC,
                CMD_SUPPORTED_COMMANDS,
                CONFIGURE_TIMEOUT_MS,
            )
            if (resp == null) {
                Log.w(TAG, "post-bind: supported-commands batch timeout — continuing")
                break
            }
            mergeSupportedCommandsResponse(resp, out)
        }
        return out
    }

    private fun mergeSupportedCommandsResponse(
        frame: HuaweiFraming.Frame,
        out: MutableMap<Int, MutableSet<Int>>,
    ) {
        val container = frame.tlvs.firstOrNull { it.tag == 0x81 }?.value ?: return
        val inner = try {
            HuaweiFraming.decodeTlvs(container)
        } catch (_: Exception) {
            return
        }
        var currentSvc = -1
        for (tlv in inner) {
            when (tlv.tag) {
                0x02 -> currentSvc = tlv.value.firstOrNull()?.toInt()?.and(0xFF) ?: -1
                0x03 -> if (currentSvc >= 0) {
                    val set = out.getOrPut(currentSvc) { LinkedHashSet() }
                    for (b in tlv.value) set.add(b.toInt() and 0xFF)
                }
            }
        }
    }

    private fun supportsCommand(serviceId: Int, commandId: Int): Boolean {
        if (commandsByService.isEmpty()) return false
        return commandsByService[serviceId]?.contains(commandId) == true
    }

    /** GB Extended Account `0x1A:0x05` — empty account byte; gated by cmd 0x05+0x06 when known. */
    private fun runExtendedAccount(activeIds: Set<Int>) {
        val gated = supportsCommand(SVC_ACCOUNT, CMD_EXTENDED_ACCOUNT) &&
            supportsCommand(SVC_ACCOUNT, CMD_ACCOUNT_SWITCH)
        val fallback = activeIds.contains(SVC_ACCOUNT) && commandsByService.isEmpty()
        if (!gated && !fallback) {
            Log.i(TAG, "post-bind: skip extended-account (cmd gate / no svc 0x1A)")
            return
        }
        val pairOpt = expandCapabilityBit(EXPAND_BIT_ACCOUNT_PAIR_OPT)
        val accountTlvs = mutableListOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(0x00)),
        )
        if (pairOpt) {
            accountTlvs += HuaweiFraming.Tlv(0x03, byteArrayOf(0x01))
        }
        val account = exchangeEncrypted(
            HuaweiFraming.Frame(SVC_ACCOUNT, CMD_EXTENDED_ACCOUNT, accountTlvs),
            SVC_ACCOUNT,
            CMD_EXTENDED_ACCOUNT,
            CONFIGURE_TIMEOUT_MS,
        )
        if (account == null) {
            Log.w(TAG, "post-bind: no extended-account response — continuing")
        } else {
            Log.i(TAG, "post-bind: extended-account ok pairOpt=$pairOpt")
        }
    }

    /** GB SettingRelated `0x01:0x31` — empty-tag probe immediately after Extended Account. */
    private fun runSettingRelated() {
        val known = supportsCommand(SVC, CMD_SETTING_RELATED)
        if (!known && commandsByService.isNotEmpty()) {
            Log.d(TAG, "post-bind: skip setting-related (cmd 0x31 unsupported)")
            return
        }
        val tags = listOf(0x01, 0x02, 0x03, 0x04, 0x05, 0x06).map {
            HuaweiFraming.Tlv(it, byteArrayOf())
        }
        val resp = exchangeEncrypted(
            HuaweiFraming.Frame(SVC, CMD_SETTING_RELATED, tags),
            SVC,
            CMD_SETTING_RELATED,
            CONFIGURE_TIMEOUT_MS,
        )
        if (resp == null) {
            Log.w(TAG, "post-bind: no setting-related response — continuing")
        } else {
            Log.i(TAG, "post-bind: setting-related ok tags=${resp.tlvs.size}")
        }
    }

    /** GB master ReverseCapabilities `0x01:0x3F` after AcceptAgreements. */
    private fun runReverseCapabilities() {
        val known = supportsCommand(SVC, CMD_REVERSE_CAPABILITIES)
        // Soft-try even if probe omitted 0x3F — master always queues when supported.
        val resp = exchangeEncrypted(
            HuaweiFraming.Frame(
                SVC,
                CMD_REVERSE_CAPABILITIES,
                listOf(HuaweiFraming.Tlv(0x01, REVERSE_CAPABILITIES)),
            ),
            SVC,
            CMD_REVERSE_CAPABILITIES,
            CONFIGURE_TIMEOUT_MS,
        )
        if (resp == null) {
            Log.w(
                TAG,
                "post-bind: no reverse-capabilities response — continuing (probed=$known)",
            )
        } else {
            Log.i(TAG, "post-bind: reverse-capabilities ok")
        }
    }

    /** GB master Country Code `0x1A:0x0A` — late in dynamic init. */
    private fun runCountryCode(activeIds: Set<Int>) {
        val ok = supportsCommand(SVC_ACCOUNT, CMD_COUNTRY_CODE) ||
            activeIds.contains(SVC_ACCOUNT) ||
            commandsByService.isEmpty()
        if (!ok) {
            Log.d(TAG, "post-bind: skip country-code")
            return
        }
        val locale = java.util.Locale.getDefault()
        val country = locale.country.ifBlank { "IN" }.uppercase(java.util.Locale.ROOT)
        val siteId = when (country) {
            "RU" -> 8
            in setOf(
                "AD", "AL", "AT", "AU", "BA", "BE", "BG", "CA", "CH", "CY", "CZ", "DE", "DK",
                "EE", "ES", "FI", "FO", "FR", "GB", "GL", "GR", "HR", "HU", "IE", "IS", "IT",
                "LI", "LT", "LU", "LV", "MC", "MD", "ME", "MK", "MT", "NL", "NO", "NZ", "PL",
                "PT", "RO", "RS", "SE", "SI", "SK", "SM", "TR", "UA", "VA",
            ) -> 7
            else -> 5
        }
        val countryTlvs = listOf(
            HuaweiFraming.Tlv(0x01, country.toByteArray(Charsets.UTF_8)),
            HuaweiFraming.Tlv(0x02, byteArrayOf(siteId.toByte())),
        )
        val cc = exchangeEncrypted(
            HuaweiFraming.Frame(SVC_ACCOUNT, CMD_COUNTRY_CODE, countryTlvs),
            SVC_ACCOUNT,
            CMD_COUNTRY_CODE,
            CONFIGURE_TIMEOUT_MS,
        )
        if (cc == null) {
            Log.w(TAG, "post-bind: no country-code response — continuing (country=$country)")
        } else {
            Log.i(TAG, "post-bind: country-code ok country=$country siteId=$siteId")
        }
    }

    private fun expandCapabilityBit(bit: Int): Boolean {
        val caps = expandCapabilities ?: return false
        if (bit >= caps.size * 8) return false
        val mask = 1 shl (bit % 8)
        return (caps[bit / 8].toInt() and mask) == mask
    }

    private fun flushPendingFeatureManagerUpload() {
        if (!pendingFeatureManagerAction2) return
        pendingFeatureManagerAction2 = false
        Log.i(TAG, "datasync featureManager action=2 — flushing deferred upload")
        startFeatureManagerUpload()
    }

    private fun startFeatureManagerUpload() {
        featureUpload.startAfterAction2Handshake {
            Log.i(
                TAG,
                "tx datasync featureManager action=2 ack " +
                    "(configId=$FEATURE_CONFIG_ID data=01) + start file upload",
            )
            sendEncryptedNoWait(
                HuaweiFraming.Frame(
                    SVC_DATASYNC,
                    CMD_DATASYNC_CONFIG,
                    featureUpload.action2AckTlvs(),
                ),
            )
        }
    }

    /**
     * Classic GB P2P (`svc=0x34`, cmd=`0x01`). Internal cmdId 1/2 → ack cmdId 3
     * with integer code `0xca` in tag 0x08. Active on this GT5 mask.
     */
    private fun maybeAckP2P(frame: HuaweiFraming.Frame) {
        if (frame.serviceId != SVC_P2P || frame.commandId != CMD_P2P) return
        if (frame.tlvs.any { it.tag == 0x7c || it.tag == 0x7d || it.tag == 0x7e }) return
        val cmdId = frame.tlvs.firstOrNull { it.tag == 0x01 }?.value?.firstOrNull()?.toInt()?.and(0xFF)
            ?: return
        if (cmdId == P2P_CMD_ACK) return
        if (cmdId !in setOf(0x01, 0x02)) return

        val seq = frame.tlvs.firstOrNull { it.tag == 0x02 }?.value ?: return
        val src = frame.tlvs.firstOrNull { it.tag == 0x03 }?.value ?: return
        val dst = frame.tlvs.firstOrNull { it.tag == 0x04 }?.value ?: return

        val reply = listOf(
            HuaweiFraming.Tlv(0x01, byteArrayOf(P2P_CMD_ACK.toByte())),
            HuaweiFraming.Tlv(0x02, seq),
            HuaweiFraming.Tlv(0x03, dst), // swap: respond as original destination
            HuaweiFraming.Tlv(0x04, src),
            HuaweiFraming.Tlv(0x08, HuaweiPacketCrypto.intBe(P2P_ACK_CODE)),
        )
        Log.i(
            TAG,
            "tx p2p ack for cmdId=$cmdId src=${src.toString(Charsets.UTF_8).take(40)}",
        )
        sendEncryptedNoWait(HuaweiFraming.Frame(SVC_P2P, CMD_P2P, reply))
    }

    /**
     * Async MusicControl — GB AsynchronousResponse.handleMusicControls:
     * - cmd 0x01 (MusicStatus): ACK with RESULT_OK (watch asked for now-playing)
     * - cmd 0x03 (Control): ACK only real button/volume pushes
     *
     * Never ACK decrypt failures or bare result frames (busy-loop poison).
     */
    private fun maybeAckMusicAsync(frame: HuaweiFraming.Frame) {
        if (frame.serviceId != SVC_MUSIC) return
        when (frame.commandId) {
            CMD_MUSIC_STATUS -> {
                // Result-only frames are acks — do not re-ack (busy-loop).
                if (frame.tlvs.size == 1 && frame.tlvs[0].tag == TAG_RESULT) {
                    Log.d(TAG, "music-status ack ignored")
                    return
                }
                if (frame.tlvs.any { it.tag == TAG_RESULT }) {
                    val code = frame.tlvs.firstOrNull { it.tag == TAG_RESULT }?.value
                    if (code != null && code.size == 4) {
                        val v = ((code[0].toInt() and 0xFF) shl 24) or
                            ((code[1].toInt() and 0xFF) shl 16) or
                            ((code[2].toInt() and 0xFF) shl 8) or
                            (code[3].toInt() and 0xFF)
                        if (v != HuaweiPacketCrypto.RESULT_OK && v != -1 && v != 0) {
                            Log.w(TAG, "music-status error code=$v — not acking")
                            return
                        }
                    }
                }
                Log.i(TAG, "tx music-status-ack cmd=0x01 (watch requested music info)")
                ackMusicStatus(CMD_MUSIC_STATUS)
            }
            CMD_MUSIC_CONTROL -> {
                if (shouldAckMusicControl(frame)) {
                    ackMusicStatus(CMD_MUSIC_CONTROL)
                }
            }
        }
    }

    private fun buildPhoneInfoTlvs(requestedTags: List<Int>): List<HuaweiFraming.Tlv> {
        val out = ArrayList<HuaweiFraming.Tlv>(requestedTags.size)
        for (tag in requestedTags) {
            when (tag) {
                0x00, 0x0F -> Unit // skipped by protocol
                0x11 -> out.add(
                    HuaweiFraming.Tlv(0x11, HuaweiPacketCrypto.intBe(PHONE_INFO_APP_VERSION)),
                )
                0x15 -> out.add(HuaweiFraming.Tlv(0x15, byteArrayOf())) // empty OS platform
                else -> out.add(HuaweiFraming.Tlv(tag, byteArrayOf(0x00)))
            }
        }
        return out
    }

    /** True only for watch button/volume pushes — never for t=7f result frames. */
    private fun shouldAckMusicControl(frame: HuaweiFraming.Frame): Boolean {
        if (frame.tlvs.any { it.tag == TAG_RESULT }) return false
        val button = frame.tlvs.firstOrNull { it.tag == TAG_MUSIC_BUTTON }
            ?.value
            ?.lastOrNull()
            ?.toInt()
            ?.and(0xFF)
        val buttonPresent = button != null && button != MUSIC_BUTTON_EXIT
        val volumePresent = frame.tlvs.any { it.tag == TAG_MUSIC_VOLUME }
        return buttonPresent || volumePresent
    }

    private fun ackMusicStatus(commandId: Int) {
        val key = sessionKey ?: return
        try {
            val plain = listOf(HuaweiFraming.Tlv(TAG_RESULT, HuaweiPacketCrypto.intBe(HuaweiPacketCrypto.RESULT_OK)))
            val iv = HuaweiPacketCrypto.nextIv(deviceSupportType, encryptionCounter)
            val encTlvs = HuaweiPacketCrypto.encryptTlvs(plain, key, iv, useGcm())
            val encoded = HuaweiFraming.encode(HuaweiFraming.Frame(SVC_MUSIC, commandId, encTlvs))
            Log.i(TAG, "tx music-status-ack cmd=0x${commandId.toString(16)} ${encoded.size}B")
            transport.write(encoded)
        } catch (e: Exception) {
            Log.w(TAG, "music-status ack failed: ${e.message}")
        }
    }

    private fun sendEncryptedNoWait(request: HuaweiFraming.Frame) {
        val key = sessionKey ?: return
        try {
            val iv = HuaweiPacketCrypto.nextIv(deviceSupportType, encryptionCounter)
            val encTlvs = HuaweiPacketCrypto.encryptTlvs(request.tlvs, key, iv, useGcm())
            val encoded = HuaweiFraming.encode(
                HuaweiFraming.Frame(request.serviceId, request.commandId, encTlvs),
            )
            Log.i(
                TAG,
                "tx(enc,no-wait) svc=0x${request.serviceId.toString(16)} " +
                    "cmd=0x${request.commandId.toString(16)} ${encoded.size}B",
            )
            transport.write(encoded)
        } catch (e: Exception) {
            Log.w(TAG, "sendEncryptedNoWait failed: ${e.message}")
        }
    }

    /** Clear inbound queue then send encrypted TLV frame (FileDownload block request). */
    private fun sendEncryptedClearing(request: HuaweiFraming.Frame) {
        synchronized(frameLock) { frameQueue.clear() }
        sendEncryptedNoWait(request)
    }

    /** Clear inbound queue then send plaintext TLV frame (FileDownload noEncrypt path). */
    private fun sendPlainClearing(request: HuaweiFraming.Frame) {
        synchronized(frameLock) { frameQueue.clear() }
        try {
            val encoded = HuaweiFraming.encode(request)
            Log.i(
                TAG,
                "tx(plain,no-wait) svc=0x${request.serviceId.toString(16)} " +
                    "cmd=0x${request.commandId.toString(16)} ${encoded.size}B",
            )
            transport.write(encoded)
        } catch (e: Exception) {
            Log.w(TAG, "sendPlainClearing failed: ${e.message}")
        }
    }

    /** Await next FileDownload block push; returns decrypted raw body. */
    private fun awaitFileDownloadBlock(serviceId: Int, timeoutMs: Long): ByteArray? {
        val frame = awaitFrame(serviceId, HuaweiFileDownload.CMD_BLOCK, timeoutMs) ?: return null
        return frame.rawBody
    }

    /** Encrypt raw (non-TLV) payload as 7C/7D/7E — FileUpload chunk path. */
    private fun sendEncryptedRawBody(serviceId: Int, commandId: Int, plainBody: ByteArray) {
        val key = sessionKey ?: return
        try {
            val iv = HuaweiPacketCrypto.nextIv(deviceSupportType, encryptionCounter)
            val encTlvs = HuaweiPacketCrypto.encryptRaw(plainBody, key, iv, useGcm())
            val encoded = HuaweiFraming.encode(
                HuaweiFraming.Frame(serviceId, commandId, encTlvs),
            )
            Log.i(
                TAG,
                "tx(enc,raw) svc=0x${serviceId.toString(16)} cmd=0x${commandId.toString(16)} " +
                    "${encoded.size}B plain=${plainBody.size}B",
            )
            transport.write(encoded)
        } catch (e: Exception) {
            Log.w(TAG, "sendEncryptedRawBody failed: ${e.message}")
        }
    }

    private fun exchange(
        request: HuaweiFraming.Frame,
        expectCmd: Int,
        timeoutMs: Long = AUTH_TIMEOUT_MS,
    ): HuaweiFraming.Frame? {
        synchronized(frameLock) { frameQueue.clear() }
        val encoded = HuaweiFraming.encode(request)
        Log.i(TAG, "tx svc=0x${request.serviceId.toString(16)} cmd=0x${request.commandId.toString(16)} hex=${encoded.toHexFull()}")
        transport.write(encoded)
        return awaitFrame(SVC, expectCmd, timeoutMs)
    }

    private fun exchangeEncrypted(
        request: HuaweiFraming.Frame,
        expectService: Int,
        expectCmd: Int,
        timeoutMs: Long,
    ): HuaweiFraming.Frame? {
        val key = sessionKey ?: return null
        synchronized(frameLock) { frameQueue.clear() }
        val iv = HuaweiPacketCrypto.nextIv(deviceSupportType, encryptionCounter)
        val encTlvs = HuaweiPacketCrypto.encryptTlvs(request.tlvs, key, iv, useGcm())
        val wire = HuaweiFraming.Frame(request.serviceId, request.commandId, encTlvs)
        val encoded = HuaweiFraming.encode(wire)
        Log.i(
            TAG,
            "tx(enc) svc=0x${request.serviceId.toString(16)} cmd=0x${request.commandId.toString(16)} " +
                "${encoded.size}B plainTags=${request.tlvs.size}",
        )
        transport.write(encoded)
        return awaitFrame(expectService, expectCmd, timeoutMs)
    }

    private fun awaitAnyFrame(timeoutMs: Long): Boolean {
        if (synchronized(frameLock) { frameQueue.isNotEmpty() }) return true
        val latch = CountDownLatch(1)
        inbound.set(latch)
        val got = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        inbound.set(null)
        return got
    }

    /** Await next frame for [serviceId] (any command). Drops other services. */
    private fun awaitServiceFrame(serviceId: Int, timeoutMs: Long): HuaweiFraming.Frame? {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (true) {
            synchronized(frameLock) {
                while (frameQueue.isNotEmpty()) {
                    val head = frameQueue.removeFirst()
                    if (head.serviceId == serviceId) return head
                }
            }
            val remainingMs = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())
            if (remainingMs <= 0) return null
            val latch = CountDownLatch(1)
            inbound.set(latch)
            latch.await(remainingMs.coerceAtMost(1000), TimeUnit.MILLISECONDS)
            inbound.set(null)
        }
    }

    private fun awaitFrame(serviceId: Int, commandId: Int, timeoutMs: Long): HuaweiFraming.Frame? {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (true) {
            synchronized(frameLock) {
                // Drop unrelated frames so a stray encrypted notify (e.g. 0x25)
                // cannot block the queue forever after the matching response arrives.
                while (frameQueue.isNotEmpty()) {
                    val head = frameQueue.first()
                    if (head.serviceId == serviceId && head.commandId == commandId) {
                        frameQueue.removeFirst()
                        return head
                    }
                    Log.d(
                        TAG,
                        "awaitFrame skip svc=0x${head.serviceId.toString(16)} " +
                            "cmd=0x${head.commandId.toString(16)} (want 0x${commandId.toString(16)})",
                    )
                    frameQueue.removeFirst()
                }
            }
            val remainingMs = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())
            if (remainingMs <= 0) return null
            val latch = CountDownLatch(1)
            inbound.set(latch)
            latch.await(remainingMs.coerceAtMost(1000), TimeUnit.MILLISECONDS)
            inbound.set(null)
        }
    }

    private data class LinkParams(
        val authVersion: HuaweiNormalAuth.AuthVersion,
        val serverNonce: ByteArray,
        val deviceSupportType: Int,
        val bondState: Int,
        val authAlgo: Int,
        val maxFrameSize: Int,
        val encryptMethod: Int,
    )

    private fun parseLinkParams(frame: HuaweiFraming.Frame): LinkParams? {
        val map = frame.tlvs.associateBy { it.tag }
        val nonceTlv = map[0x05] ?: return null
        if (nonceTlv.value.size < 2 + HuaweiNormalAuth.NONCE_LENGTH) return null
        val authVersion = HuaweiNormalAuth.AuthVersion.fromCode(nonceTlv.value[1].toInt() and 0xFF) ?: return null
        val serverNonce = nonceTlv.value.copyOfRange(2, 2 + HuaweiNormalAuth.NONCE_LENGTH)
        val maxFrame = map[0x02]?.value?.let {
            if (it.size >= 2) ((it[0].toInt() and 0xFF) shl 8) or (it[1].toInt() and 0xFF) else 0x00F4
        } ?: 0x00F4
        return LinkParams(
            authVersion = authVersion,
            serverNonce = serverNonce,
            deviceSupportType = map[0x07]?.value?.firstOrNull()?.toInt()?.and(0xFF) ?: 0,
            bondState = map[0x09]?.value?.firstOrNull()?.toInt()?.and(0xFF) ?: 0,
            authAlgo = map[0x08]?.value?.firstOrNull()?.toInt()?.and(0xFF) ?: 0,
            maxFrameSize = maxFrame,
            encryptMethod = map[0x0C]?.value?.firstOrNull()?.toInt()?.and(0xFF) ?: 0,
        )
    }

    private fun verifyAuthResponse(
        authVersion: HuaweiNormalAuth.AuthVersion,
        frame: HuaweiFraming.Frame,
        clientNonce: ByteArray,
        serverNonce: ByteArray,
    ): Boolean {
        val challenge = frame.tlvs.firstOrNull { it.tag == 0x01 }?.value ?: return false
        return challenge.contentEquals(HuaweiNormalAuth.digestResponse(authVersion, clientNonce, serverNonce))
    }

    private fun resultCode(frame: HuaweiFraming.Frame): Int? {
        val result = frame.tlvs.firstOrNull { it.tag == TAG_RESULT } ?: return null
        var value = 0
        for (b in result.value) value = (value shl 8) or (b.toInt() and 0xFF)
        return value
    }

    private fun logTlvs(frame: HuaweiFraming.Frame) {
        val parts = frame.tlvs.joinToString(" ") { "t=${it.tag.toString(16)}:${it.value.toHexFull()}" }
        Log.i(TAG, "frame ok svc=0x${frame.serviceId.toString(16)} cmd=0x${frame.commandId.toString(16)} tlvs=[$parts]")
    }

    private fun failAndDisconnect(message: String, hint: String): SessionOutcome {
        Log.w(TAG, "auth_failed: $message hint=$hint")
        emit(mapOf("type" to "session_state", "state" to "auth_failed", "message" to message, "hint" to hint))
        try { transport.disconnect() } catch (_: Exception) {}
        return SessionOutcome.AuthFailed
    }

    private fun activeCommandsProbe(): Map<Int, ByteArray> {
        if (!liftEnabled) return COMMANDS_PROBE
        val base = COMMANDS_PROBE[HuaweiNotifyLift.SVC_NOTIFY] ?: byteArrayOf()
        val replyByte = HuaweiNotifyLift.CMD_REPLY.toByte()
        val withReply = if (base.any { it == replyByte }) {
            base
        } else {
            base + replyByte
        }
        return COMMANDS_PROBE + (HuaweiNotifyLift.SVC_NOTIFY to withReply)
    }

    fun liftConfigure(enabled: Boolean) {
        liftEnabled = enabled
        Log.i(TAG, "liftConfigure enabled=$enabled")
        if (enabled && sessionKey != null && encryptionEnabled) {
            reprobeNotifyServiceCommands()
        }
    }

    internal fun liftCapabilitySnapshot(): Map<String, Any?> {
        val svc02 = commandsByService[HuaweiNotifyLift.SVC_NOTIFY] ?: emptySet()
        val caps = expandCapabilities
        return mapOf(
            "liftEnabled" to liftEnabled,
            "svc02Active" to (HuaweiNotifyLift.SVC_NOTIFY in commandsByService.keys ||
                commandsByService.isEmpty()),
            "svc02Commands" to svc02.sorted(),
            "bit73ReplyActions" to expandCapabilityBit(73),
            "bit77Timestamp" to expandCapabilityBit(77),
            "bit82SmsQuick" to expandCapabilityBit(82),
            "bit89ReplyKey" to expandCapabilityBit(89),
            "bit94KeyedNotify" to expandCapabilityBit(94),
            "bit120Remove" to expandCapabilityBit(120),
            "expandCapabilityLen" to (caps?.size ?: 0),
        )
    }

    fun liftSendTestNotification(
        title: String,
        sender: String,
        body: String,
        withReplyKey: Boolean,
        notifyType: Int,
        key: String,
        category: String?,
    ): Map<String, Any?> {
        if (!liftEnabled) {
            return mapOf("error" to "disabled")
        }
        val caps = liftCapsFromExpand(withReplyKey)
        val constraints = fetchNotifyConstraints()
        val sentAtMs = System.currentTimeMillis()
        val msgId = liftMsgIdCounter.getAndIncrement()
        val frame = HuaweiNotifyLift.buildSendNotification(
            msgId = msgId,
            type = notifyType,
            title = title,
            sender = sender,
            body = body,
            sourceAppId = HuaweiNotifyLift.SRC_PHONE_PKG,
            key = key,
            caps = caps,
            nowSec = sentAtMs / 1000L,
            contentFormat = constraints.contentFormat ?: 0x02,
            contentMaxLen = constraints.contentMaxLen,
            notificationId = msgId,
            category = category,
        )
        lastLiftNotification = HuaweiNotifyLift.LastSentNotification(
            msgId, notifyType, key, msgId, category,
        )
        liftSendEncrypted(frame)
        return mapOf(
            "msgId" to msgId,
            "key" to key,
            "contentMaxLen" to constraints.contentMaxLen,
            "sentAtMs" to sentAtMs,
        )
    }

    fun liftRemoveLast(): Map<String, Any?> {
        if (!liftEnabled) return mapOf("error" to "disabled")
        val last = lastLiftNotification ?: return mapOf("error" to "no_last")
        if (!expandCapabilityBit(120)) return mapOf("error" to "bit120_off")
        val frame = HuaweiNotifyLift.buildRemove(
            last.notifyType,
            HuaweiNotifyLift.SRC_PHONE_PKG,
            last.key,
            last.notificationId,
            last.category,
        )
        liftSendEncrypted(frame)
        return mapOf("removed" to true, "key" to last.key)
    }

    fun liftQueryQuickReplies(): Map<String, Any?> {
        if (!liftEnabled) return mapOf("error" to "disabled")
        val payload = HuaweiNotifyLift.buildQuickReplyQuery()
        val p2p = HuaweiNotifyLift.buildP2PSend(
            liftP2pSeq.getAndIncrement(),
            HuaweiNotifyLift.MODULE_SMS_QUICK,
            HuaweiNotifyLift.DST_WATCH_HOME,
            HuaweiNotifyLift.FINGERPRINT_PHONE,
            HuaweiNotifyLift.FINGERPRINT_WATCH,
            payload,
        )
        liftSendEncrypted(p2p)
        return mapOf("sent" to true)
    }

    fun liftSetQuickReplies(replies: List<String>): Map<String, Any?> {
        if (!liftEnabled) return mapOf("error" to "disabled")
        val payload = HuaweiNotifyLift.buildQuickReplyUpdate(replies)
        val p2p = HuaweiNotifyLift.buildP2PSend(
            liftP2pSeq.getAndIncrement(),
            HuaweiNotifyLift.MODULE_SMS_QUICK,
            HuaweiNotifyLift.DST_WATCH_HOME,
            HuaweiNotifyLift.FINGERPRINT_PHONE,
            HuaweiNotifyLift.FINGERPRINT_WATCH,
            payload,
        )
        liftSendEncrypted(p2p)
        return mapOf("sent" to true, "count" to replies.size.coerceAtMost(5))
    }

    fun flushPendingLiftSend() {
        val frame = pendingLiftSend.getAndSet(null) ?: return
        sendEncryptedNoWait(frame)
    }

    private fun reprobeNotifyServiceCommands() {
        if (!liftEnabled) return
        val cmds = activeCommandsProbe()[HuaweiNotifyLift.SVC_NOTIFY] ?: return
        val batch = listOf(
            HuaweiFraming.Tlv(0x02, byteArrayOf(HuaweiNotifyLift.SVC_NOTIFY.toByte())),
            HuaweiFraming.Tlv(0x03, cmds),
        )
        val nested = HuaweiFraming.encodeTlvs(batch)
        val resp = exchangeEncrypted(
            HuaweiFraming.Frame(
                SVC,
                CMD_SUPPORTED_COMMANDS,
                listOf(HuaweiFraming.Tlv(0x81, nested)),
            ),
            SVC,
            CMD_SUPPORTED_COMMANDS,
            CONFIGURE_TIMEOUT_MS,
        )
        if (resp != null) {
            val merged = commandsByService.toMutableMap()
            mergeSupportedCommandsResponse(resp, merged)
            commandsByService = merged
            Log.i(
                TAG,
                "lift: re-probed svc 0x02 cmds=${commandsByService[HuaweiNotifyLift.SVC_NOTIFY]}",
            )
        }
    }

    private fun liftCapsFromExpand(withReplyKey: Boolean): HuaweiNotifyLift.LiftCaps =
        HuaweiNotifyLift.LiftCaps(
            bit73ReplyActions = expandCapabilityBit(73),
            bit77Timestamp = expandCapabilityBit(77),
            bit82SmsQuick = expandCapabilityBit(82),
            bit89ReplyKey = withReplyKey && expandCapabilityBit(89),
            bit94KeyedNotify = expandCapabilityBit(94),
            bit120Remove = expandCapabilityBit(120),
        )

    private fun fetchNotifyConstraints(): HuaweiNotifyLift.NotifyConstraints {
        cachedNotifyConstraints?.let { return it }
        val req = HuaweiNotifyLift.buildConstraintsRequest()
        val resp = exchangeEncrypted(
            req,
            HuaweiNotifyLift.SVC_NOTIFY,
            HuaweiNotifyLift.CMD_CONSTRAINTS,
            CONFIGURE_TIMEOUT_MS,
        )
        val parsed = if (resp != null) {
            val n = HuaweiNotifyLift.parseConstraints(resp)
            NotifyConstraints(n.contentMaxLen, n.contentFormat)
        } else {
            NotifyConstraints(null, null)
        }
        cachedNotifyConstraints = parsed
        return parsed
    }

    private data class NotifyConstraints(
        val contentMaxLen: Int?,
        val contentFormat: Int?,
    )

    private fun liftSendEncrypted(frame: HuaweiFraming.Frame) {
        if (!liftEnabled) return
        if (isSyncHeld()) {
            pendingLiftSend.set(frame)
            Log.i(TAG, "lift send queued — sync in flight")
            return
        }
        sendEncryptedNoWait(frame)
    }

    private fun maybeEmitLiftSvc02Frame(frame: HuaweiFraming.Frame) {
        if (frame.serviceId != HuaweiNotifyLift.SVC_NOTIFY) return
        val tags = frame.tlvs.joinToString(",") { "0x${it.tag.toString(16)}:${it.value.size}" }
        emit(
            mapOf(
                "type" to "lift_frame",
                "svc" to frame.serviceId,
                "cmd" to frame.commandId,
                "tlvSummary" to tags,
                "rxAtMs" to System.currentTimeMillis(),
            ),
        )
    }

    private fun maybeHandleNotificationReply(frame: HuaweiFraming.Frame, decryptOk: Boolean) {
        val reply = HuaweiNotifyLift.parseReply(frame) ?: return
        emit(
            mapOf(
                "type" to "lift_reply",
                "key" to reply.key,
                "text" to reply.text,
                "replyType" to reply.replyType,
                "encoding" to reply.encoding,
                "rxAtMs" to System.currentTimeMillis(),
                "rxElapsedNs" to SystemClock.elapsedRealtimeNanos(),
            ),
        )
        if (liftEnabled && decryptOk) {
            liftSendEncrypted(HuaweiNotifyLift.buildReplyAck(0x00))
        }
    }

    private fun maybeHandleLiftP2PInbound(frame: HuaweiFraming.Frame) {
        if (frame.serviceId != SVC_P2P || frame.commandId != CMD_P2P) return
        val src = frame.tlvs.firstOrNull { it.tag == 0x03 }?.value?.toString(Charsets.UTF_8).orEmpty()
        val dst = frame.tlvs.firstOrNull { it.tag == 0x04 }?.value?.toString(Charsets.UTF_8).orEmpty()
        if (!src.contains("smsquick") && !dst.contains("smsquick")) return
        val payload = frame.tlvs.firstOrNull { it.tag == 0x07 }?.value ?: return
        val items = HuaweiNotifyLift.parseQuickReplyList(payload)
        if (items.isNotEmpty()) {
            emit(mapOf("type" to "lift_quick_replies", "items" to items))
        }
    }

    fun persistSessionMaterialForTest(material: String) {
        secrets.setAuthMaterial(material)
    }

    enum class SessionOutcome { Ready, AuthFailed }
}

internal fun ByteArray.toHexFull(): String = joinToString("") { "%02X".format(it) }
