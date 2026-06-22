plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    buildTypes {
        debug {
            // Skip PNG crunching & shrinking in debug for faster builds
            isShrinkResources = false
            isMinifyEnabled = false
            isCrunchPngs = false
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
