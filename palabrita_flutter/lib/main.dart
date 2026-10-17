import 'dart:io';

import 'package:flutter/material.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PalabritaBenchmarkApp());
}

class PalabritaBenchmarkApp extends StatelessWidget {
  const PalabritaBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Palabrita Research Benchmark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BenchmarkDashboardScreen(),
    );
  }
}

class BenchmarkDashboardScreen extends StatefulWidget {
  const BenchmarkDashboardScreen({super.key});

  @override
  State<BenchmarkDashboardScreen> createState() => _BenchmarkDashboardScreenState();
}

class _BenchmarkDashboardScreenState extends State<BenchmarkDashboardScreen> {
  final TextEditingController _modelPathController = TextEditingController(
    text: '/data/local/tmp/qwen3_0_6b.bin',
  );

  int _runsPerPrompt = 5;
  bool _useGpu = false;
  bool _isRunning = false;

  int _currentTurn = 0;
  int _totalTurns = 150; // 30 prompts * 5 runs default
  String _currentPromptInfo = 'Ready to run benchmark';

  int _successCount = 0;
  int _f1Count = 0;
  int _f2Count = 0;
  int _f4Count = 0;
  double _lastLatencyMs = 0;
  int _lastGcPauseUs = 0;

  String? _exportedCsvPath;
  final List<String> _consoleLogs = [];

  InferenceLogger? _logger;
  InferenceEngine? _engine;

  @override
  void initState() {
    super.initState();
    _logger = InferenceLogger();
  }

  @override
  void dispose() {
    _modelPathController.dispose();
    _engine?.dispose();
    super.dispose();
  }

  void _logToConsole(String message) {
    setState(() {
      _consoleLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $message');
      if (_consoleLogs.length > 50) {
        _consoleLogs.removeLast();
      }
    });
  }

  Future<void> _startBenchmark() async {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _currentTurn = 0;
      _successCount = 0;
      _f1Count = 0;
      _f2Count = 0;
      _f4Count = 0;
      _lastLatencyMs = 0;
      _lastGcPauseUs = 0;
      _exportedCsvPath = null;
      _consoleLogs.clear();
    });

    _logToConsole('Initializing benchmark pipeline...');

    try {
      // 1. Load prompts
      final prompts = await BenchmarkRunner.loadPrompts();
      final total = prompts.length * _runsPerPrompt;
      setState(() {
        _totalTurns = total;
      });

      _logToConsole('Loaded ${prompts.length} benchmark prompts ($total total runs).');

      // 2. Initialize InferenceEngine
      final bindings = LiteRtLmBindings.open();
      _engine?.dispose();
      _engine = InferenceEngine(bindings: bindings);

      await _engine!.initialize(
        modelPath: _modelPathController.text.trim(),
        useGpu: _useGpu,
      );

      _logToConsole('InferenceEngine ready (backend: ${_useGpu ? 'GPU' : 'CPU'}, mock: ${bindings.isMock}).');

      final parser = DefensiveParser();
      final promptEngine = PromptEngine();
      final sessionManager = SessionManager(logger: _logger!);

      await sessionManager.startSession(reason: 'Device benchmark run initiated');

      int turnCounter = 0;

      for (final promptItem in prompts) {
        if (!_isRunning) break;

        final sysPrompt = promptEngine.hintSystemPrompt(promptItem.language);
        final userPrompt = promptEngine.hintUserPrompt(promptItem.word, promptItem.language);

        for (var runIdx = 1; runIdx <= _runsPerPrompt; runIdx++) {
          if (!_isRunning) break;

          turnCounter++;

          setState(() {
            _currentTurn = turnCounter;
            _currentPromptInfo = '${promptItem.id}: "${promptItem.word}" (${promptItem.language}) [run $runIdx/$_runsPerPrompt]';
          });

          // Run turn
          final result = await _engine!.generateSingleTurn(
            systemPrompt: sysPrompt,
            userPrompt: userPrompt,
          );

          final parseResult = parser.parseHints(result.text);

          ParseDecision decision;
          FailureCategory failureCat;
          String parsedText = '';

          if (parseResult is ParseSuccess<List<String>>) {
            final hints = parseResult.data;
            parsedText = hints.join(' | ');

            final leaksWord = hints.any(
              (h) => h.toLowerCase().contains(promptItem.word.toLowerCase()),
            );

            if (leaksWord) {
              decision = ParseDecision.failure;
              failureCat = FailureCategory.F2;
              _f2Count++;
            } else {
              decision = ParseDecision.success;
              failureCat = FailureCategory.none;
              _successCount++;
            }
          } else {
            decision = ParseDecision.failure;
            if (sessionManager.consecutiveFailures >= 3) {
              failureCat = FailureCategory.F4;
              _f4Count++;
            } else if (result.text.contains(':') && result.text.contains('|')) {
              failureCat = FailureCategory.F2;
              _f2Count++;
            } else {
              failureCat = FailureCategory.F1;
              _f1Count++;
            }
          }

          _lastLatencyMs = result.latencyMs.toDouble();
          _lastGcPauseUs = result.gcPauseEstimateUs;

          // Telemetry
          await _logger!.logInference(
            sessionId: sessionManager.currentSessionId,
            turnNumber: turnCounter,
            rawOutput: result.text,
            parsedOutput: parsedText,
            parseDecision: decision,
            failureCategory: failureCat,
            latencyMs: result.latencyMs,
            gcPauseEstimateUs: result.gcPauseEstimateUs,
            metadata: {
              'prompt_id': promptItem.id,
              'word': promptItem.word,
              'language': promptItem.language,
              'run_index': runIdx,
            },
          );

          await sessionManager.recordTurn(
            isSuccess: decision == ParseDecision.success,
            failureReason: failureCat != FailureCategory.none ? failureCat.name : null,
          );

          setState(() {});

          if (decision != ParseDecision.success) {
            _logToConsole('⚠️ [${promptItem.id}] Failure (${failureCat.name}): ${result.text.replaceAll('\n', ' ').trim()}');
          }
        }
      }

      await sessionManager.endSession(reason: 'Device benchmark finished');

      // Export CSV
      final csv = await _logger!.exportToCSV();
      setState(() {
        _exportedCsvPath = csv.path;
      });

      _logToConsole('✅ Benchmark complete! Exported to: ${csv.path}');
    } catch (e, st) {
      _logToConsole('❌ Error: $e');
      debugPrint('$e\n$st');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _exportCsvDirect() async {
    if (_logger == null) return;
    try {
      final file = await _logger!.exportToCSV();
      setState(() {
        _exportedCsvPath = file.path;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV Exported: ${file.path}'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      _logToConsole('Failed to export CSV: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _totalTurns > 0 ? (_currentTurn / _totalTurns).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Palabrita AI Benchmark'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export CSV',
            onPressed: _exportCsvDirect,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Device Info Card
            _buildDeviceInfoCard(theme),
            const SizedBox(height: 12),

            // 2. Configuration & Launch Card
            _buildConfigCard(theme),
            const SizedBox(height: 16),

            // 3. Live Progress Indicator
            LinearProgressIndicator(
              value: _isRunning ? progress : (_currentTurn > 0 ? 1.0 : 0.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress: $_currentTurn / $_totalTurns turns (${(progress * 100).toStringAsFixed(1)}%)',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  _isRunning ? 'RUNNING' : (_currentTurn > 0 ? 'COMPLETED' : 'IDLE'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _isRunning ? Colors.amber : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              _currentPromptInfo,
              style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),

            // 4. Metric Counters Grid (Clean, F1, F2, F4)
            _buildTaxonomyMetrics(theme),
            const SizedBox(height: 16),

            // 5. Latency & GC Gauge
            _buildTelemetryGauge(theme),
            const SizedBox(height: 16),

            // 6. Console Stream Feed
            _buildConsoleFeed(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard(ThemeData theme) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.perm_device_information, size: 20),
                const SizedBox(width: 8),
                Text('Test Environment', style: theme.textTheme.titleMedium),
              ],
            ),
            const Divider(),
            Text('Device: ${_logger?.deviceInfo ?? 'Unknown'}', style: theme.textTheme.bodySmall),
            Text("Platform: ${Platform.operatingSystem} (${Platform.version.split(' ').first})", style: theme.textTheme.bodySmall),
            Text('Model Target: Qwen3 0.6B (LiteRT-LM Single-Shot)', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Benchmark Settings', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _modelPathController,
              enabled: !_isRunning,
              decoration: const InputDecoration(
                labelText: 'Model Weights Path',
                hintText: '/data/local/tmp/qwen3_0_6b.bin',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text('Runs / Prompt: '),
                      DropdownButton<int>(
                        value: _runsPerPrompt,
                        items: const [1, 2, 5, 10].map((v) {
                          return DropdownMenuItem(value: v, child: Text('$v'));
                        }).toList(),
                        onChanged: _isRunning
                            ? null
                            : (val) {
                                if (val != null) setState(() => _runsPerPrompt = val);
                              },
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Text('Use GPU: '),
                    Switch(
                      value: _useGpu,
                      onChanged: _isRunning
                          ? null
                          : (val) {
                              setState(() => _useGpu = val);
                            },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isRunning ? () => setState(() => _isRunning = false) : _startBenchmark,
              icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_isRunning ? 'Stop Benchmark' : 'Start Full Benchmark (30 Prompts)'),
              style: FilledButton.styleFrom(
                backgroundColor: _isRunning ? Colors.red.shade700 : theme.colorScheme.primary,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxonomyMetrics(ThemeData theme) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      children: [
        _metricTile('Clean Success', '$_successCount', Colors.green, Icons.check_circle),
        _metricTile('F1 (Format Violation)', '$_f1Count', Colors.orange, Icons.format_paint),
        _metricTile('F2 (Structural Error)', '$_f2Count', Colors.amber, Icons.schema),
        _metricTile('F4 (KV/Session Degradation)', '$_f4Count', Colors.redAccent, Icons.history_toggle_off),
      ],
    );
  }

  Widget _metricTile(String title, String count, Color color, IconData icon) {
    return Card(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(count, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                  Text(title, style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryGauge(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                const Text('Last Latency', style: TextStyle(fontSize: 12)),
                Text('${_lastLatencyMs.toStringAsFixed(1)} ms', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            Column(
              children: [
                const Text('GC Pause Estimate', style: TextStyle(fontSize: 12)),
                Text('$_lastGcPauseUs µs', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            Column(
              children: [
                const Text('CSV Exported', style: TextStyle(fontSize: 12)),
                Text(_exportedCsvPath != null ? 'Yes' : 'Pending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _exportedCsvPath != null ? Colors.green : Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsoleFeed(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Live Execution Feed', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${_consoleLogs.length} events', style: theme.textTheme.bodySmall),
              ],
            ),
            const Divider(),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
              child: _consoleLogs.isEmpty
                  ? const Center(child: Text('No events yet. Press Start to begin.', style: TextStyle(fontSize: 12, color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _consoleLogs.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, i) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            _consoleLogs[i],
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
