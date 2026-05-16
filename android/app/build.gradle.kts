import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties()
val keyFile = file("C:/nusha3/key.properties")
if (keyFile.exists()) keyProps.load(FileInputStream(keyFile))

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
            keyAlias     = keyProps.getProperty("keyAlias")     ?: "nusha3"
            keyPassword  = keyProps.getProperty("keyPassword")  ?: "nusha3pass"
            storeFile    = file(keyProps.getProperty("storeFile") ?: "C:/nusha3/nusha3-release.jks")
            storePassword= keyProps.getProperty("storePassword")?: "nusha3pass"
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
