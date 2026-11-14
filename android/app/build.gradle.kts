import java.util.Properties
import java.io.FileInputStream
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fitness_os"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.fitness_os"
        // flutter_gemma / LiteRT-LM needs API 24+
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Load keystore from environment or fall back to debug signing
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val keystoreProperties = Properties()
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            } else {
                // CI or local without keystore: use environment variables or debug signing
                val keystoreBase64 = System.getenv("ANDROID_KEYSTORE_BASE64")
                if (keystoreBase64 != null) {
                    val keystoreFile = file("${rootProject.buildDir}/app-release.keystore")
                    keystoreFile.parentFile.mkdirs()
                    keystoreFile.writeBytes(Base64.getDecoder().decode(keystoreBase64))
                    
                    storeFile = keystoreFile
                    storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: "android"
                    keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "upload"
                    keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: storePassword
                } else {
                    // Fallback to debug signing
                    println("⚠️  WARNING: No release keystore found. Using debug signing.")
                    println("   Add ANDROID_KEYSTORE_* secrets or create android/key.properties")
                    storeFile = signingConfigs.getByName("debug").storeFile
                    storePassword = signingConfigs.getByName("debug").storePassword
                    keyAlias = signingConfigs.getByName("debug").keyAlias
                    keyPassword = signingConfigs.getByName("debug").keyPassword
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Disable minify for now to avoid breaking Huawei BLE stack and Sentry
            // TODO: Add proper proguard rules and re-enable
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("io.sentry:sentry-android:7.19.1")
    testImplementation("junit:junit:4.13.2")
}
