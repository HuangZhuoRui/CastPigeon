import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
    alias(libs.plugins.kotlinSerialization)
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}
dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation(projects.sharedLogic)
    implementation(projects.sharedUI)

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.compose.runtime)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation("com.github.topjohnwu.libsu:core:6.0.0")
    implementation("com.github.topjohnwu.libsu:service:6.0.0")
    implementation(libs.compose.ui)
    implementation(libs.compose.uiToolingPreview)
    debugImplementation(libs.compose.uiTooling)
    
    implementation("androidx.compose.material:material-icons-extended:1.6.0")
    
    implementation(libs.miuix.blur)
    implementation(libs.miuix.ui)
    
    implementation(libs.haze)
    implementation(libs.haze.materials)
}

android {
    namespace = "com.suseoaa.castpigeon"
    compileSdk = libs.versions.android.compileSdk.get().toInt()

    buildFeatures {
        aidl = true
    }

    defaultConfig {
        applicationId = "com.suseoaa.castpigeon"
        minSdk = libs.versions.android.minSdk.get().toInt()
        targetSdk = libs.versions.android.targetSdk.get().toInt()
        versionCode = 1
        versionName = "1.0"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
    signingConfigs {
        create("suseRelease") {
            storeFile = file("/Users/vincent/Desktop/SUSE-APP-Key/APP-Key.jks")
            storePassword = "LinuxisUbuntu18"
            keyAlias = "suse-app-key"
            keyPassword = "LinuxisUbuntu18"
        }
    }
    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("suseRelease")
        }
        getByName("release") {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
