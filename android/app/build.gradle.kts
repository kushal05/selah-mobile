import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, if a keystore has been configured on this machine.
//
// Without one, release builds fall back to the debug keystore — which is
// generated per machine. Two developers then produce APKs with different
// signatures, and Android refuses to install one over the other with the
// unhelpful message "App not installed". That is exactly what happened
// between build 29 (built elsewhere) and builds 30/31 (built here).
//
// To fix it for good, create one keystore, share it securely, and give each
// machine an android/key.properties holding:
//   storeFile=/absolute/path/to/selah-release.jks
//   storePassword=…
//   keyAlias=…
//   keyPassword=…
// key.properties and *.jks are gitignored; the keystore must never be
// committed, and must never be lost — without it the app can never be
// updated again.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.example.notify"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        // applicationId is set per flavor below.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // Only ship arm64-v8a for release; covers 95%+ of active devices.
            // armeabi-v7a and x86_64 add ~15MB each with no user benefit.
            abiFilters += listOf("arm64-v8a")
        }
    }

    flavorDimensions += "environment"

    productFlavors {
        create("production") {
            dimension = "environment"
            applicationId = "in.selahapp.app"
            resValue("string", "app_name", "Selah")
        }
        create("qa") {
            dimension = "environment"
            applicationId = "in.selahapp.app.qa"
            resValue("string", "app_name", "Selah QA")
        }
    }

    applicationVariants.all {
        val flavor = flavorName
        val build = buildType.name
        outputs.all {
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl)
                .outputFileName = "selah-$flavor-$build.apk"
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Skip PNG crunching & shrinking in debug for faster builds
            isShrinkResources = false
            isMinifyEnabled = false
            isCrunchPngs = false
        }
        release {
            // The shared release keystore when one is configured, otherwise the
            // machine's debug keystore so `flutter run --release` still works.
            // See the note at the top of this file: the fallback is what makes
            // an APK from one machine refuse to install over another's.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKeystore) "release" else "debug"
            )
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
