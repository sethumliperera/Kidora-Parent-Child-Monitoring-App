plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin must come after Android + Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

configurations.all {
    resolutionStrategy {
        force("androidx.activity:activity:1.9.3")
        force("androidx.activity:activity-ktx:1.9.3")
        force("androidx.fragment:fragment:1.8.5")
        force("androidx.fragment:fragment-ktx:1.8.5")
    }
}

android {
    namespace = "com.example.kidora_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.kidora_app"
        minSdk = flutter.minSdkVersion  // Increased from flutter.minSdkVersion (required for flutter_background_service)
        targetSdk = 33
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
