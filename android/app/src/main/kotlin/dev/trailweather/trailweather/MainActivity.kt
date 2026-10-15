package dev.trailweather.trailweather

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException

/**
 * 接收“用徒步天气打开”（ACTION_VIEW）与分享（ACTION_SEND）传入的轨迹文件。
 *
 * 只把 URI 与文件名交给 Dart；字节由 Dart 按需调用 readBytes 读取（后台线程，上限 30 MB），
 * 格式识别与解析全部在 Dart 侧（RouteFileImport）完成。本文件由仓库提交，
 * CI 中 `flutter create` 不会覆盖已存在的文件。
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingFile: Map<String, String>? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    result.success(pendingFile)
                    pendingFile = null
                }
                "readBytes" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("bad_args", "missing uri", null)
                    } else {
                        Thread {
                            try {
                                val bytes = readLimited(Uri.parse(uri))
                                mainHandler.post { result.success(bytes) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("read_failed", e.message ?: e.javaClass.simpleName, null)
                                }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
        pendingFile = takeFile(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val file = takeFile(intent) ?: return
        channel?.invokeMethod("onFile", file)
    }

    /** 取出 intent 中的文件并标记已消费，避免 Activity 重建时重复导入。 */
    private fun takeFile(intent: Intent?): Map<String, String>? {
        if (intent == null || intent.getBooleanExtra(CONSUMED, false)) return null
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> streamExtra(intent)
            else -> null
        } ?: return null
        intent.putExtra(CONSUMED, true)
        return mapOf("uri" to uri.toString(), "name" to displayName(uri))
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c ->
                    if (c.moveToFirst()) {
                        val name = c.getString(0)
                        if (!name.isNullOrBlank()) return name
                    }
                }
        } catch (_: Exception) {
            // file:// 或不支持查询的提供方：回退到路径末段
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "shared-file"
    }

    private fun readLimited(uri: Uri): ByteArray {
        val input = contentResolver.openInputStream(uri) ?: throw IOException("无法打开文件")
        input.use { stream ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            var total = 0
            while (true) {
                val n = stream.read(buf)
                if (n < 0) break
                total += n
                if (total > MAX_BYTES) throw IOException("文件超过 30 MB 大小限制")
                out.write(buf, 0, n)
            }
            return out.toByteArray()
        }
    }

    companion object {
        private const val CHANNEL = "trailweather/incoming_file"
        private const val CONSUMED = "dev.trailweather.incoming_consumed"
        private const val MAX_BYTES = 30 * 1024 * 1024
    }
}
