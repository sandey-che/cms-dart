import 'dart:async';
import 'dart:convert';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:teta_cms/src/platform/index.dart';
import 'package:teta_cms/src/users/settings.dart';
import 'package:teta_cms/src/users/user.dart';
import 'package:teta_cms/src/utils.dart';
import 'package:teta_cms/teta_cms.dart';
import 'package:uni_links/uni_links.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:url_launcher/url_launcher.dart';

class TetaAuth {
  TetaAuth(
    this.token,
    this.prjId,
  ) {
    project = TetaProjectSettings(token, prjId);
    user = TetaUserUtils(token, prjId);
  }
  final String token;
  final int prjId;
  late TetaProjectSettings project;
  late TetaUserUtils user;

  Future<bool> insertUser(final String userToken) async {
    final uri = Uri.parse(
      '${U.baseUrl}auth/users/$prjId',
    );

    final res = await http.post(
      uri,
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: json.encode(
        <String, dynamic>{
          'token': userToken,
        },
      ),
    );

    TetaCMS.printWarning('insertUser body: ${res.body}');

    if (res.statusCode != 200) {
      throw Exception('insertUser resulted in ${res.statusCode} ${res.body}');
    }

    if (res.body != '{"warn":"User already registered"}') {
      await TetaCMS.instance.analytics.insertEvent(
        TetaAnalyticsType.tetaAuthSignUp,
        'Teta Auth: signup request',
        <String, dynamic>{},
        isUserIdPreferableIfExists: false,
      );
      return false;
    }
    await _persistentLogin(userToken);
    return true;
  }

  Future<List<dynamic>> retrieveUsers({
    required final int prjId,
    final int limit = 10,
    final int page = 0,
  }) async {
    final uri = Uri.parse(
      '${U.baseUrl}auth/users/$prjId',
    );

    final res = await http.get(
      uri,
      headers: {
        'authorization': 'Bearer $token',
        'page': '$page',
        'page-elems': '$limit',
      },
    );

    TetaCMS.printWarning('retrieveUsers body: ${res.body}');

    if (res.statusCode != 200) {
      throw Exception('retrieveUsers resulted in ${res.statusCode}');
    }

    final list = json.decode(res.body) as List<dynamic>;
    TetaCMS.log('retrieveUsers list: $list');
    final users =
        (list.first as Map<String, dynamic>)['users'] as List<dynamic>;
    TetaCMS.log('retrieveUsers users: $users');

    await TetaCMS.instance.analytics.insertEvent(
      TetaAnalyticsType.tetaAuthRetrieveUsers,
      'Teta Auth: retrieve users request',
      <String, dynamic>{
        'weight': res.bodyBytes.lengthInBytes,
      },
      isUserIdPreferableIfExists: false,
    );

    return users;
  }

  /// Returns auth url from specific provider
  Future<String> _signIn({
    required final int prjId,
    required final TetaProvider provider,
  }) async {
    TetaCMS.log('signIn');
    final param = EnumToString.convertToString(provider);
    final device = UniversalPlatform.isWeb ? 'web' : 'mobile';
    final res = await http.post(
      Uri.parse('https://auth.teta.so/auth/$param/$prjId/$device'),
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
    );

    TetaCMS.log(res.body);

    if (res.statusCode != 200) {
      throw Exception('signIn resulted in ${res.statusCode}');
    }

    return res.body;
  }

  /// Performs login in mobile and web platforms
  Future signIn({
    /// Performs a function on success
    required final Function() onSuccess,

    /// The external provider
    final TetaProvider provider = TetaProvider.google,
  }) async {
    final url = await _signIn(prjId: prjId, provider: provider);
    await CMSPlatform.login(url, (final userToken) async {
      if (!UniversalPlatform.isWeb) {
        uriLinkStream.listen(
          (final Uri? uri) async {
            if (uri != null) {
              if (uri.queryParameters['access_token'] != null &&
                  uri.queryParameters['access_token'] is String) {
                await closeInAppWebView();
                final isFirstTime = await TetaCMS.instance.auth.insertUser(
                  // ignore: cast_nullable_to_non_nullable
                  uri.queryParameters['access_token'] as String,
                );
                unawaited(
                  TetaCMS.instance.analytics.insertEvent(
                    TetaAnalyticsType.tetaAuthSignIn,
                    'Teta Auth: signIn request',
                    <String, dynamic>{
                      'device': 'mobile',
                      'provider': EnumToString.convertToString(provider),
                    },
                    isUserIdPreferableIfExists: false,
                  ),
                );
                onSuccess();
              }
            }
          },
          onError: (final Object err) {
            throw Exception(r'got err: $err');
          },
        );
      } else {
        TetaCMS.log('Callback on web');
        final isFirstTime = await insertUser(userToken);
        unawaited(
          TetaCMS.instance.analytics.insertEvent(
            TetaAnalyticsType.tetaAuthSignIn,
            'Teta Auth: signIn request',
            <String, dynamic>{
              'device': 'web',
              'provider': EnumToString.convertToString(provider),
            },
            isUserIdPreferableIfExists: false,
          ),
        );
        onSuccess();
      }
    });
  }

  /// Set access_token for persistent login
  Future _persistentLogin(final String token) async {
    final box = await Hive.openBox<dynamic>('Teta Auth');
    await box.put('access_tkn', token);
  }

  Future logout() async {
    final box = await Hive.openBox<dynamic>('Teta Auth');
    await box.delete('access_tkn');
  }

  /// Make a query with Ayaya
  Future<TetaResponse<List<dynamic>, TetaErrorResponse?>> get(
    final String ayayaQuery,
  ) async {
    final uri = Uri.parse(
      '${U.baseUrl}auth/aya',
    );

    final res = await http.post(
      uri,
      headers: {
        'authorization': 'Bearer $token',
        'x-identifier': '$prjId',
      },
      body: '''
      ON prj_id* $prjId;
      $ayayaQuery
      ''',
    );

    if (res.statusCode != 200) {
      return TetaResponse<List<dynamic>, TetaErrorResponse>(
        data: <dynamic>[],
        error: TetaErrorResponse(
          code: res.statusCode,
          message: res.body,
        ),
      );
    }

    await TetaCMS.instance.analytics.insertEvent(
      TetaAnalyticsType.tetaAuthQueryAyaya,
      'Teta Auth: custom Query with Ayaya',
      <String, dynamic>{
        'weight': res.bodyBytes.lengthInBytes + utf8.encode(ayayaQuery).length,
      },
      isUserIdPreferableIfExists: false,
    );

    TetaCMS.printWarning(res.body);

    return TetaResponse<List<dynamic>, TetaErrorResponse?>(
      data: ((json.decode(res.body) as List<dynamic>?)?.first
              as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
          <dynamic>[],
      error: null,
    );
  }
}
