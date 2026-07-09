import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Embedded login screen using webview_flutter.
/// Loads the Keycloak login URL and intercepts the custom redirect URI
/// to extract the authorization code without leaving the app.
class LoginWebviewScreen extends StatefulWidget {
  const LoginWebviewScreen({
    super.key,
    required this.authUrl,
    required this.redirectUri,
  });

  final String authUrl;
  final String redirectUri;

  @override
  State<LoginWebviewScreen> createState() => _LoginWebviewScreenState();
}

class _LoginWebviewScreenState extends State<LoginWebviewScreen> {
  late final WebViewController _controller;
  int _loadingProgress = 0;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F0C1B))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress;
              });
            }
          },
          onPageStarted: (String url) {
            _checkRedirect(url);
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _loadingProgress = 100;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            // Filter out internal platform-specific system warnings that aren't critical
            if (error.errorCode == -10 && error.description.contains('unknown URL scheme')) {
              // This is usually the custom scheme trigger, which we already handle.
              return;
            }
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_checkRedirect(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  /// Checks if the URL matches our custom redirect URI, extracts code/state, and returns it.
  bool _checkRedirect(String url) {
    if (url.startsWith(widget.redirectUri)) {
      final uri = Uri.parse(url);
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];
      final errorDescription = uri.queryParameters['error_description'];

      if (error != null) {
        Navigator.of(context).pop({
          'error': error,
          'error_description': errorDescription ?? 'An error occurred during sign in.',
        });
        return true;
      }

      if (code != null) {
        Navigator.of(context).pop({
          'code': code,
          'state': state,
        });
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0C1B),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF16122C),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Keycloak Secure Sign In',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _loadingProgress = 0;
                });
                _controller.reload();
              },
            ),
          ],
          bottom: _loadingProgress < 100 && !_hasError
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3.0),
                  child: LinearProgressIndicator(
                    value: _loadingProgress / 100.0,
                    backgroundColor: const Color(0xFF16122C),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2EB5FF)),
                    minHeight: 3.0,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            if (!_hasError)
              WebViewWidget(controller: _controller)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load login page',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage.isNotEmpty ? _errorMessage : 'Unknown error occurred.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _hasError = false;
                            _loadingProgress = 0;
                          });
                          _controller.reload();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2EB5FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
