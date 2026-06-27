import org.jetbrains.kotlin.gradle.dsl.JvmTarget

val releaseRepository = providers.gradleProperty("githubRepository")
    .orElse(providers.environmentVariable("GITHUB_REPOSITORY"))
    .orElse("suse-edu-cn/CastPigeon")
val localReleaseKeystorePath = "/Users/vincent/Desktop/SUSE-APP-Key/APP-Key.jks"
val releaseKeystorePath = System.getenv("KEYSTORE_FILE_PATH")
    ?.takeIf { it.isNotBlank() }
    ?: localReleaseKeystorePath.takeIf { file(it).exists() }

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
    implementation(libs.api)
    implementation(libs.provider)
    implementation(projects.sharedLogic)
    implementation(projects.sharedUI)

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.compose.runtime)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.libsu.core)
    implementation(libs.libsu.service)
    implementation(libs.compose.ui)
    implementation(libs.compose.uiToolingPreview)
    debugImplementation(libs.compose.uiTooling)
    
    implementation(libs.androidx.material.icons.extended)
    
    implementation(libs.miuix.blur)
    implementation(libs.miuix.ui)
    implementation(libs.multiplatform.markdown.renderer.m3)
    
    implementation(libs.haze)
    implementation(libs.haze.materials)
}

android {
    namespace = "com.suseoaa.castpigeon"
    compileSdk = libs.versions.android.compileSdk.get().toInt()

    buildFeatures {
        aidl = true
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.suseoaa.castpigeon"
        minSdk = libs.versions.android.minSdk.get().toInt()
        //noinspection OldTargetApi
        targetSdk = libs.versions.android.targetSdk.get().toInt()
        versionCode = 106
        versionName = "1.0.6"
        buildConfigField("String", "GITHUB_REPOSITORY", "\"${releaseRepository.get()}\"")
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
    signingConfigs {
        create("release") {
            if (!releaseKeystorePath.isNullOrBlank()) {
                storeFile = file(releaseKeystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: "LinuxisUbuntu18"
                keyAlias = System.getenv("KEY_ALIAS") ?: "suse-app-key"
                keyPassword = System.getenv("KEY_PASSWORD") ?: "LinuxisUbuntu18"
            }
        }
    }
    buildTypes {
        getByName("debug") {
            if (!releaseKeystorePath.isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            if (!releaseKeystorePath.isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
