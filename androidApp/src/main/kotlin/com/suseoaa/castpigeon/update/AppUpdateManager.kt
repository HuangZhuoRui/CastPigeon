package com.suseoaa.castpigeon.update

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import com.suseoaa.castpigeon.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

object AppUpdateManager {
    data class UpdateAsset(
        val versionName: String,
        val assetName: String,
        val downloadUrl: String,
        val digest: String?
    )

    data class ReleaseInfo(
        val versionName: String,
        val tagName: String,
        val title: String,
        val body: String,
        val asset: UpdateAsset,
        val publishedAt: String?
    )

    data class UpdateInfo(
        val latestRelease: ReleaseInfo,
        val mergedBody: String,
        val includedReleases: List<ReleaseInfo>
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val androidAssetRegex = Regex("""^CastPigeon-Android-v(.+)\.apk$""")
    private val unifiedReleaseTagRegex = Regex("""^v(.+)$""", RegexOption.IGNORE_CASE)

    suspend fun checkForUpdate(context: Context): Result<UpdateInfo?> = withContext(Dispatchers.IO) {
        runCatching {
            val releases = fetchPlatformReleases()
            val currentVersion = currentVersionName(context)
            val newerReleases = releases
                .filter { compareVersions(it.versionName, currentVersion) > 0 }
                .sortedWith(releaseVersionDescendingComparator())

            val latestRelease = newerReleases.firstOrNull() ?: return@runCatching null
            UpdateInfo(
                latestRelease = latestRelease,
                mergedBody = mergeReleaseBodies(newerReleases),
                includedReleases = newerReleases
            )
        }
    }

    suspend fun getHistoryReleases(): Result<List<ReleaseInfo>> = withContext(Dispatchers.IO) {
        runCatching { fetchPlatformReleases() }
    }

    fun currentVersionName(context: Context): String {
        return runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0"
        }.getOrDefault("0")
    }

    fun enqueueApkDownload(context: Context, releaseInfo: ReleaseInfo): Long {
        val downloadsDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        val file = File(downloadsDir, releaseInfo.asset.assetName)
        if (file.exists()) file.delete()

        val request = DownloadManager.Request(Uri.parse(releaseInfo.asset.downloadUrl))
            .setTitle("正在下载 CastPigeon ${releaseInfo.versionName}")
            .setDescription(releaseInfo.asset.assetName)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, releaseInfo.asset.assetName)
            .setMimeType("application/vnd.android.package-archive")

        val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        return downloadManager.enqueue(request)
    }

    fun getDownloadProgress(context: Context, downloadId: Long): Int {
        val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = downloadManager.query(DownloadManager.Query().setFilterById(downloadId))
        if (cursor != null && cursor.moveToFirst()) {
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                cursor.close()
                return 100
            }
            val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            cursor.close()
            return if (total > 0L) ((downloaded * 100L) / total).toInt() else 0
        }
        cursor?.close()
        return -1
    }

    suspend fun verifyDownloadedApk(context: Context, downloadId: Long, expectedDigest: String?): Boolean = withContext(Dispatchers.IO) {
        val normalizedDigest = expectedDigest?.removePrefix("sha256:")?.lowercase()?.takeIf { it.isNotBlank() }
            ?: return@withContext true
        val file = downloadedFile(context, downloadId) ?: return@withContext false
        val actualDigest = sha256(file)
        actualDigest == normalizedDigest
    }

    fun installDownloadedApk(context: Context, downloadId: Long): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            return true
        }

        val file = downloadedFile(context, downloadId) ?: return false
        val apkUri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return true
    }

    private fun downloadedFile(context: Context, downloadId: Long): File? {
        val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        runCatching {
            val cursor = downloadManager.query(DownloadManager.Query().setFilterById(downloadId))
            if (cursor != null && cursor.moveToFirst()) {
                val localUri = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                cursor.close()
                if (!localUri.isNullOrBlank()) {
                    val file = File(Uri.parse(localUri).path.orEmpty())
                    if (file.exists()) return file
                }
            } else {
                cursor?.close()
            }
        }
        return context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?.listFiles()
            ?.filter { it.extension.equals("apk", ignoreCase = true) }
            ?.maxByOrNull { it.lastModified() }
    }

    private fun fetchPlatformReleases(): List<ReleaseInfo> {
        return fetchReleases()
            .asSequence()
            .filterNot { it.draft || it.prerelease }
            .mapNotNull { release -> release.toAndroidReleaseInfo() }
            .sortedWith(releaseVersionDescendingComparator())
            .toList()
    }

    private fun GitHubRelease.toAndroidReleaseInfo(): ReleaseInfo? {
        val tagVersion = unifiedReleaseTagRegex.matchEntire(tagName)?.groupValues?.getOrNull(1)
            ?: return null
        val matchedAsset = assets.firstNotNullOfOrNull { asset ->
            val version = androidAssetRegex.matchEntire(asset.name)?.groupValues?.getOrNull(1)
                ?: return@firstNotNullOfOrNull null
            // 统一发布后只接受 v版本号 Tag，并要求 Tag 版本与 Android 安装包版本一致，避免旧分平台 Release 干扰。
            if (version != tagVersion) return@firstNotNullOfOrNull null
            UpdateAsset(
                versionName = version,
                assetName = asset.name,
                downloadUrl = asset.downloadUrl,
                digest = asset.digest
            )
        } ?: return null

        return ReleaseInfo(
            versionName = matchedAsset.versionName,
            tagName = tagName,
            title = name.ifBlank { tagName },
            body = body.orEmpty(),
            asset = matchedAsset,
            publishedAt = publishedAt
        )
    }

    private fun fetchReleases(): List<GitHubRelease> {
        val connection = URL("https://api.github.com/repos/${BuildConfig.GITHUB_REPOSITORY}/releases")
            .openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        connection.setRequestProperty("User-Agent", "CastPigeon-Android")
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000

        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream.bufferedReader().use { it.readText() }
        connection.disconnect()
        if (status !in 200..299) {
            error("GitHub Releases 请求失败: HTTP $status")
        }
        return json.decodeFromString(body)
    }

    private fun mergeReleaseBodies(releases: List<ReleaseInfo>): String {
        val featureItems = linkedSetOf<String>()
        val fixItems = linkedSetOf<String>()
        val otherSections = mutableListOf<String>()

        releases.forEach { release ->
            val parsed = parseReleaseBody(release.body)
            featureItems.addAll(parsed.features)
            fixItems.addAll(parsed.fixes)
            if (parsed.others.isNotBlank()) {
                otherSections.add("#### ${release.title}\n${parsed.others}")
            }
        }

        return buildString {
            if (featureItems.isNotEmpty()) {
                appendLine("### 功能更新")
                featureItems.forEach { appendLine("- $it") }
                appendLine()
            }
            if (fixItems.isNotEmpty()) {
                appendLine("### 问题修复")
                fixItems.forEach { appendLine("- $it") }
                appendLine()
            }
            if (otherSections.isNotEmpty()) {
                appendLine("### 其他更新")
                otherSections.forEach { section ->
                    appendLine(section)
                    appendLine()
                }
            }
        }.trim()
    }

    private fun parseReleaseBody(body: String): ParsedReleaseBody {
        val features = mutableListOf<String>()
        val fixes = mutableListOf<String>()
        val others = mutableListOf<String>()
        var currentSection = ""

        body.lineSequence().forEach { rawLine ->
            val line = rawLine.trim()
            if (line.startsWith("#")) {
                currentSection = line
                return@forEach
            }

            val itemText = line.removePrefix("-").removePrefix("*").trim()
            if (itemText.isBlank()) return@forEach

            // CI 生成的 Markdown 使用固定中文标题，这里按标题把历史日志归并到同类列表。
            when {
                currentSection.contains("功能") -> features += itemText
                currentSection.contains("修复") || currentSection.contains("问题") -> fixes += itemText
                else -> others += rawLine
            }
        }

        return ParsedReleaseBody(
            features = features,
            fixes = fixes,
            others = others.joinToString("\n").trim()
        )
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var count = input.read(buffer)
            while (count != -1) {
                digest.update(buffer, 0, count)
                count = input.read(buffer)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun compareVersions(remote: String, current: String): Int {
        val left = remote.versionParts()
        val right = current.versionParts()
        val size = maxOf(left.size, right.size)
        for (index in 0 until size) {
            val a = left.getOrElse(index) { 0 }
            val b = right.getOrElse(index) { 0 }
            if (a != b) return a - b
        }
        return 0
    }

    private fun releaseVersionDescendingComparator(): Comparator<ReleaseInfo> {
        return Comparator { left, right ->
            compareVersions(right.versionName, left.versionName)
        }
    }

    private fun String.versionParts(): List<Int> {
        return removePrefix("v")
            .removePrefix("V")
            .split('.', '-', '_')
            .map { part -> part.takeWhile { it.isDigit() }.toIntOrNull() ?: 0 }
    }

    private data class ParsedReleaseBody(
        val features: List<String>,
        val fixes: List<String>,
        val others: String
    )

    @Serializable
    private data class GitHubRelease(
        @SerialName("tag_name")
        val tagName: String,
        val name: String = "",
        val body: String? = "",
        val draft: Boolean = false,
        val prerelease: Boolean = false,
        @SerialName("published_at")
        val publishedAt: String? = null,
        val assets: List<GitHubAsset> = emptyList()
    )

    @Serializable
    private data class GitHubAsset(
        val name: String,
        @SerialName("browser_download_url")
        val downloadUrl: String,
        val digest: String? = null
    )
}
