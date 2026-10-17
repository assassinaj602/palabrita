package com.palabrita.research.palabrita_flutter

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val channelName = "com.palabrita.research/litertlm"
    private var engine: Engine? = null
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val modelPath = call.argument<String>("modelPath") ?: run {
                        result.error("INVALID_ARGUMENT", "modelPath is required", null)
                        return@setMethodCallHandler
                    }
                    val useGpu = call.argument<Boolean>("useGpu") ?: false

                    scope.launch {
                        try {
                            withContext(Dispatchers.IO) {
                                engine?.close()
                                val backend = if (useGpu) Backend.GPU() else Backend.CPU()
                                val config = EngineConfig(
                                    modelPath = modelPath,
                                    backend = backend,
                                    cacheDir = cacheDir.absolutePath,
                                )
                                val newEngine = Engine(config)
                                newEngine.initialize()
                                engine = newEngine
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Failed to initialize LiteRT-LM engine", e)
                            result.error("INIT_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                }
                "sendMessage" -> {
                    val currentEngine = engine
                    if (currentEngine == null) {
                        result.error("NOT_INITIALIZED", "Engine is not initialized", null)
                        return@setMethodCallHandler
                    }

                    val systemPrompt = call.argument<String>("systemPrompt")
                    val userPrompt = call.argument<String>("userPrompt") ?: ""
                    val topK = call.argument<Int>("topK") ?: 40
                    val topP = call.argument<Double>("topP") ?: 0.95
                    val temperature = call.argument<Double>("temperature") ?: 0.8

                    scope.launch {
                        try {
                            val response = withContext(Dispatchers.IO) {
                                val convConfig = ConversationConfig(
                                    systemInstruction = systemPrompt?.let { Contents.of(it) },
                                    samplerConfig = SamplerConfig(topK = topK, topP = topP, temperature = temperature),
                                )
                                currentEngine.createConversation(convConfig).use { conv ->
                                    val msg = conv.sendMessage(userPrompt)
                                    msg.toString()
                                }
                            }
                            result.success(response)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Inference execution failed", e)
                            result.error("INFERENCE_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                }
                "dispose" -> {
                    engine?.close()
                    engine = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        engine?.close()
        engine = null
        super.onDestroy()
    }
}
