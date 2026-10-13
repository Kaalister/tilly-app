package com.tilly.caisse

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingImportResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_IMPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickBackup" -> openBackupPicker(result)
                    "saveBackup" -> saveBackup(
                        call.argument("name"),
                        call.argument("content"),
                        result
                    )
                    "savePdf" -> savePdf(
                        call.argument("name"),
                        call.argument("bytes"),
                        result
                    )
                    "installApk" -> installApk(
                        call.argument("path"),
                        result
                    )
                    "openUrl" -> openUrl(
                        call.argument("url"),
                        result
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        val apk = path?.trim()
        if (apk.isNullOrBlank() || !File(apk).exists()) {
            result.error("invalid_path", "Fichier de mise à jour introuvable.", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (_: Exception) {
                // L'écran de réglage n'est pas disponible : on guide l'utilisateur.
            }
            result.error(
                "install_permission_required",
                "Autorise Tilly à installer des applications, puis réessaie.",
                null
            )
            return
        }

        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", File(apk))
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("install_failed", "Impossible de lancer l'installation.", error.message)
        }
    }

    private fun openUrl(url: String?, result: MethodChannel.Result) {
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "Lien de mise à jour invalide.", null)
            return
        }

        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            result.error("open_url_failed", "Impossible d'ouvrir le lien de mise à jour.", error.message)
        }
    }

    private fun saveBackup(name: String?, content: String?, result: MethodChannel.Result) {
        val json = content
        if (json.isNullOrBlank()) {
            result.error("empty_export", "Le contenu de l'export est vide.", null)
            return
        }

        val fileName = safeBackupFileName(name)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri == null) {
                    result.error("export_failed", "Impossible de créer le fichier dans Downloads.", null)
                    return
                }

                try {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        output.write(json.toByteArray(Charsets.UTF_8))
                    } ?: throw IllegalStateException("Flux d'écriture indisponible")

                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    result.success(mapOf("name" to fileName, "uri" to uri.toString()))
                } catch (error: Exception) {
                    contentResolver.delete(uri, null, null)
                    result.error("export_failed", "Impossible d'écrire le fichier dans Downloads.", error.message)
                }
            } else {
                val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!downloads.exists()) downloads.mkdirs()
                val file = File(downloads, fileName)
                file.writeText(json, Charsets.UTF_8)
                result.success(mapOf("name" to fileName, "path" to file.absolutePath))
            }
        } catch (error: Exception) {
            result.error("export_failed", "Impossible d'enregistrer l'export dans Downloads.", error.message)
        }
    }

    private fun safeBackupFileName(name: String?): String {
        val baseName = name
            ?.trim()
            ?.replace(Regex("[^A-Za-z0-9._-]+"), "-")
            ?.trim('-', '.', '_')
            ?.takeIf { it.isNotEmpty() }
            ?: "tilly-export.tilly"
        return if (baseName.endsWith(".tilly", ignoreCase = true)) baseName else "$baseName.tilly"
    }

    private fun savePdf(name: String?, bytes: ByteArray?, result: MethodChannel.Result) {
        val pdfBytes = bytes
        if (pdfBytes == null || pdfBytes.isEmpty()) {
            result.error("empty_export", "Le contenu du PDF est vide.", null)
            return
        }

        val fileName = safePdfFileName(name)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri == null) {
                    result.error("export_failed", "Impossible de créer le PDF dans Downloads.", null)
                    return
                }

                try {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        output.write(pdfBytes)
                    } ?: throw IllegalStateException("Flux d'écriture indisponible")

                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    result.success(mapOf("name" to fileName, "uri" to uri.toString()))
                } catch (error: Exception) {
                    contentResolver.delete(uri, null, null)
                    result.error("export_failed", "Impossible d'écrire le PDF dans Downloads.", error.message)
                }
            } else {
                val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!downloads.exists()) downloads.mkdirs()
                val file = File(downloads, fileName)
                file.writeBytes(pdfBytes)
                result.success(mapOf("name" to fileName, "path" to file.absolutePath))
            }
        } catch (error: Exception) {
            result.error("export_failed", "Impossible d'enregistrer le PDF dans Downloads.", error.message)
        }
    }

    private fun safePdfFileName(name: String?): String {
        val baseName = name
            ?.trim()
            ?.replace(Regex("[^A-Za-z0-9._-]+"), "-")
            ?.trim('-', '.', '_')
            ?.takeIf { it.isNotEmpty() }
            ?: "joueurs_airsoft.pdf"
        return if (baseName.endsWith(".pdf", ignoreCase = true)) baseName else "$baseName.pdf"
    }

    private fun openBackupPicker(result: MethodChannel.Result) {
        if (pendingImportResult != null) {
            result.error("picker_already_open", "Un sélecteur de fichier est déjà ouvert.", null)
            return
        }
        pendingImportResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }

        try {
            startActivityForResult(intent, PICK_BACKUP_REQUEST)
        } catch (error: Exception) {
            pendingImportResult = null
            result.error("picker_unavailable", "Impossible d'ouvrir le sélecteur de fichier.", error.message)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_BACKUP_REQUEST) return

        val result = pendingImportResult ?: return
        pendingImportResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("file_missing", "Aucun fichier sélectionné.", null)
            return
        }

        try {
            val content = contentResolver.openInputStream(uri)
                ?.bufferedReader(Charsets.UTF_8)
                ?.use { it.readText() }
            if (content == null) {
                result.error("file_unreadable", "Impossible de lire le fichier sélectionné.", null)
                return
            }
            result.success(
                mapOf(
                    "name" to (displayName(uri) ?: "sauvegarde.tilly"),
                    "content" to content
                )
            )
        } catch (error: Exception) {
            result.error("file_unreadable", "Impossible de lire le fichier sélectionné.", error.message)
        }
    }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) return cursor.getString(index)
        }
        return uri.lastPathSegment
    }

    companion object {
        private const val FILE_IMPORT_CHANNEL = "tilly/file_import"
        private const val PICK_BACKUP_REQUEST = 7301
    }
}
