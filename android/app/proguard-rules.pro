# R8 / ProGuard rules for Fathom release builds.
#
# Tink (pulled in by androidx.security:security-crypto) references
# errorprone annotations that are compile-only and absent from the APK.
# Without these, minifyReleaseWithR8 fails with "Missing classes detected".
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi
