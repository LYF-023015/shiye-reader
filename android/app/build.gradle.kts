import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { stream ->
        keystoreProperties.load(stream)
    }
}

android {
    namespace = "com.lyf.reading_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lyf.reading_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }


    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

val sanitizeReleasePluginRegistrant = tasks.register("sanitizeReleasePluginRegistrant") {
    dependsOn("compileFlutterBuildRelease")
    doLast {
        val registrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        if (!registrant.exists()) return@doLast
        val lines = registrant.readLines()
        val output = mutableListOf<String>()
        var index = 0
        while (index < lines.size) {
            val windowEnd = minOf(index + 7, lines.size)
            val isIntegrationBlock = lines[index].trim() == "try {" &&
                lines.subList(index, windowEnd).any { it.contains("integration_test") }
            if (!isIntegrationBlock) {
                output += lines[index]
                index++
                continue
            }
            var sawCatch = false
            index++
            while (index < lines.size) {
                val line = lines[index]
                if (line.contains("catch (Exception")) sawCatch = true
                index++
                if (sawCatch && line.trim() == "}") break
            }
        }
        registrant.writeText(output.joinToString(System.lineSeparator(), postfix = System.lineSeparator()))
    }
}

tasks.configureEach {
    if (name == "compileReleaseJavaWithJavac") {
        dependsOn(sanitizeReleasePluginRegistrant)
    }
}
