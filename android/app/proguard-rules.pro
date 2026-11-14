# R8 / ProGuard rules for Fathom release builds.
#
# Tink (pulled in by androidx.security:security-crypto) references
# errorprone annotations that are compile-only and absent from the APK.
# Without these, minifyReleaseWithR8 fails with "Missing classes detected".
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi

# Sentry: Keep exception classes and stack traces for crash reporting
-keepattributes LineNumberTable,SourceFile
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Huawei BLE stack: Keep all Huawei-related classes for BLE communication
-keep class com.example.fitness_os.huawei.** { *; }
-keep class com.example.fitness_os.observability.** { *; }
-keepclassmembers class com.example.fitness_os.huawei.** { *; }
-keepclassmembers class com.example.fitness_os.observability.** { *; }

# Keep Kotlin metadata for reflection
-keepattributes *Annotation*
-keep class kotlin.Metadata { *; }
