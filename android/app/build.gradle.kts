import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nusha.messenger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            val ksFile = file("nusha3.jks")
            if (ksFile.exists()) {
                storeFile = ksFile
                storePassword = System.getenv("KEY_STORE_PASSWORD") ?: "nusha3pass"
                keyAlias = System.getenv("KEY_ALIAS") ?: "nusha3"
                keyPassword = System.getenv("KEY_PASSWORD") ?: "nusha3pass"
            } else {
                storeFile = file("../../android/app/debug.keystore") 
            }
        }
    }

    defaultConfig {
        applicationId = "com.nusha.messenger"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = 2
        versionName = "1.1.0"
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
