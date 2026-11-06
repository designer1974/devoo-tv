package com.designer1974.devoo_tv

import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Registra un canale TV direttamente dallo stream (HLS .m3u8 o flusso diretto):
 * sceglie la qualità più alta, scarica i pezzi di video man mano e li unisce in un file.
 * Niente cattura dello schermo: il file ha solo il video del canale, senza icone.
 * I pezzi MPEG-TS diventano un file .ts, quelli fMP4 un file .mp4.
 */
object HlsRecorder {
    private const val TAG = "HlsRecorder"

    @Volatile var running = false
    @Volatile var bytes = 0L
    @Volatile var error: String? = null
    @Volatile var startedAt = 0L
    @Volatile var url = ""
    @Volatile var onTimeUp: (() -> Unit)? = null
    @Volatile private var stopAt = Long.MAX_VALUE
    @Volatile private var worker: Thread? = null
    @Volatile private var partFile: File? = null
    @Volatile private var finalPath: String? = null

    val busy: Boolean get() = worker != null

    /** [dstBase]: percorso del file senza estensione (la sceglie il registratore). */
    fun start(url: String, headers: Map<String, String>, dstBase: String, until: Long = Long.MAX_VALUE) {
        if (worker != null) throw IllegalStateException("registrazione già in corso")
        this.url = url
        bytes = 0
        error = null
        startedAt = System.currentTimeMillis()
        stopAt = until
        running = true
        finalPath = null
        val t = Thread({ run(url, headers, dstBase) }, "hls-rec")
        worker = t
        t.start()
    }

    /** Ferma e ritorna il file salvato (null se vuoto). */
    fun stop(): String? {
        running = false
        val t = worker
        try { t?.interrupt() } catch (_: Exception) {}
        try { t?.join(15000) } catch (_: Exception) {}
        worker = null
        return finalPath
    }

    // ---------------------------------------------------------------- rete

    private fun open(u: String, headers: Map<String, String>): HttpURLConnection {
        var cur = URL(u)
        repeat(5) {
            val c = cur.openConnection() as HttpURLConnection
            c.connectTimeout = 15000
            c.readTimeout = 20000
            c.instanceFollowRedirects = false
            c.setRequestProperty("User-Agent", headers["User-Agent"] ?: "Mozilla/5.0 (Linux; Android 13) DevooTV")
            headers["Referer"]?.let { c.setRequestProperty("Referer", it) }
            val code = c.responseCode
            if (code in 300..399) {
                val loc = c.getHeaderField("Location") ?: throw Exception("redirect senza indirizzo")
                c.disconnect()
                cur = URL(cur, loc)
                return@repeat
            }
            if (code !in 200..299) {
                c.disconnect()
                throw Exception("HTTP $code")
            }
            return c
        }
        throw Exception("troppi redirect")
    }

    private fun text(u: String, h: Map<String, String>): Pair<String, String> {
        val c = open(u, h)
        try {
            return c.inputStream.bufferedReader().readText() to c.url.toString()
        } finally {
            c.disconnect()
        }
    }

    private fun bytesOf(u: String, h: Map<String, String>): ByteArray {
        val c = open(u, h)
        try {
            return c.inputStream.readBytes()
        } finally {
            c.disconnect()
        }
    }

    private fun resolve(base: String, rel: String): String = URL(URL(base), rel.trim()).toString()

    private fun attr(line: String, name: String): String? =
        Regex("$name=(\"[^\"]*\"|[^,]*)").find(line)?.groupValues?.get(1)?.trim('"')

    // ---------------------------------------------------------------- registrazione

    private fun run(startUrl: String, h: Map<String, String>, dstBase: String) {
        var out: FileOutputStream? = null
        var part: File? = null
        try {
            var (body, base) = text(startUrl, h)
            if (!body.trimStart().startsWith("#EXTM3U")) {
                // non è HLS: flusso continuo (es. .ts o .mp4 in diretta)
                part = File("$dstBase.ts.part")
                partFile = part
                out = FileOutputStream(part)
                copyRaw(startUrl, h, out)
                return
            }
            // playlist principale: sceglie la qualità più alta
            if (body.contains("#EXT-X-STREAM-INF")) {
                val lines = body.lines()
                var best = -1L
                var bestUri: String? = null
                for (i in lines.indices) {
                    val l = lines[i]
                    if (!l.startsWith("#EXT-X-STREAM-INF")) continue
                    val bw = attr(l, "BANDWIDTH")?.toLongOrNull() ?: 0
                    val uri = lines.drop(i + 1).firstOrNull { it.isNotBlank() && !it.startsWith("#") } ?: continue
                    if (bw > best) { best = bw; bestUri = uri }
                }
                val media = resolve(base, bestUri ?: throw Exception("nessuna qualità"))
                val r = text(media, h)
                body = r.first
                base = r.second
            }
            val mediaUrl = base
            val done = HashSet<String>()
            var initDone = false
            var fails = 0
            var lastOk = System.currentTimeMillis()
            while (running) {
                if (System.currentTimeMillis() >= stopAt) { running = false; onTimeUp?.invoke(); break }
                var target = 6.0
                try {
                    val lines = body.lines()
                    var seq = 0L
                    var keyMethod: String? = null
                    var keyUri: String? = null
                    var keyIv: String? = null
                    var key: ByteArray? = null
                    for (l in lines) {
                        when {
                            l.startsWith("#EXT-X-TARGETDURATION:") -> target = l.substringAfter(':').trim().toDoubleOrNull() ?: 6.0
                            l.startsWith("#EXT-X-MEDIA-SEQUENCE:") -> seq = l.substringAfter(':').trim().toLongOrNull() ?: 0
                            l.startsWith("#EXT-X-MAP:") && !initDone -> {
                                val u = attr(l, "URI") ?: continue
                                if (out == null) {
                                    part = File("$dstBase.mp4.part"); partFile = part; out = FileOutputStream(part)
                                }
                                val b = bytesOf(resolve(mediaUrl, u), h)
                                out!!.write(b); bytes += b.size; initDone = true
                            }
                            l.startsWith("#EXT-X-KEY:") -> {
                                keyMethod = attr(l, "METHOD")
                                keyIv = attr(l, "IV")
                                val u = attr(l, "URI")
                                if (u != null && u != keyUri) {
                                    keyUri = u
                                    key = if (keyMethod == "AES-128") bytesOf(resolve(mediaUrl, u), h) else null
                                }
                            }
                            l.isNotBlank() && !l.startsWith("#") -> {
                                val segUrl = resolve(mediaUrl, l)
                                val id = "$seq|$l"
                                if (done.add(id)) {
                                    if (out == null) {
                                        part = File("$dstBase.ts.part"); partFile = part; out = FileOutputStream(part)
                                    }
                                    var b = bytesOf(segUrl, h)
                                    if (keyMethod == "AES-128" && key != null) b = decrypt(b, key!!, keyIv, seq)
                                    out!!.write(b)
                                    bytes += b.size
                                    lastOk = System.currentTimeMillis()
                                    if (!running || System.currentTimeMillis() >= stopAt) break
                                }
                                seq++
                            }
                        }
                    }
                    if (done.size > 3000) { // memoria: tiene solo gli ultimi
                        val keep = done.toList().takeLast(500); done.clear(); done.addAll(keep)
                    }
                    if (body.contains("#EXT-X-ENDLIST")) break
                    fails = 0
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    fails++
                    Log.w(TAG, "pezzo non scaricato: ${e.message}")
                    if (System.currentTimeMillis() - lastOk > 90_000) { error = "Il canale non risponde più"; break }
                }
                try {
                    Thread.sleep((target * 500).toLong().coerceIn(1000, 6000))
                } catch (_: InterruptedException) { break }
                if (!running) break
                try { body = text(mediaUrl, h).first } catch (e: Exception) { fails++ }
            }
        } catch (e: InterruptedException) {
            // fermata
        } catch (e: Exception) {
            Log.e(TAG, "registrazione", e)
            error = e.message ?: "Errore"
        } finally {
            try { out?.flush(); out?.close() } catch (_: Exception) {}
            running = false
            val p = part
            finalPath = if (p != null && p.exists() && p.length() > 50_000) {
                val dst = File(p.absolutePath.removeSuffix(".part"))
                if (p.renameTo(dst)) dst.absolutePath else p.absolutePath
            } else {
                try { p?.delete() } catch (_: Exception) {}
                null
            }
            partFile = null
            worker = null
        }
    }

    private fun copyRaw(u: String, h: Map<String, String>, out: FileOutputStream) {
        val c = open(u, h)
        try {
            val input = c.inputStream
            val buf = ByteArray(64 * 1024)
            while (running) {
                if (System.currentTimeMillis() >= stopAt) { running = false; onTimeUp?.invoke(); break }
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                bytes += n
            }
        } finally {
            c.disconnect()
        }
    }

    private fun decrypt(data: ByteArray, key: ByteArray, ivHex: String?, seq: Long): ByteArray {
        val iv = ByteArray(16)
        if (ivHex != null) {
            val hex = ivHex.removePrefix("0x").removePrefix("0X").padStart(32, '0')
            for (i in 0 until 16) iv[i] = hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        } else {
            var s = seq
            for (i in 15 downTo 8) { iv[i] = (s and 0xff).toByte(); s = s shr 8 }
        }
        val c = Cipher.getInstance("AES/CBC/PKCS5Padding")
        c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        return c.doFinal(data)
    }
}
