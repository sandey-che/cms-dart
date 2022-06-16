import 'dart:convert';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:http/http.dart' as http;
import 'package:teta_cms/src/utils.dart';
import 'package:teta_cms/teta_cms.dart';

class TetaAnalytics {
  TetaAnalytics(
    this.token,
    this.prjId,
  ) {
    init();
  }

  final String token;
  final int prjId;
  String? _currentUserId;

  Future init({final String? userId}) async {
    _currentUserId =
        userId ?? (await TetaCMS.instance.auth.user.get)['id'] as String?;
  }

  /// Creates a new event
  Future<TetaResponse> insertEvent(
    final TetaAnalyticsType type,
    final String name,
    final Map<String, dynamic> properties, {
    required final bool isUserIdPreferableIfExists,
  }) async {
    final uri = Uri.parse(
      '${U.analyticsUrl}events/add/${EnumToString.convertToString(type)}',
    );

    final res = await http.post(
      uri,
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        'x-identifier': '$prjId',
      },
      body: json.encode(<String, dynamic>{
        'name': name,
        'prj_id': prjId,
        if (isUserIdPreferableIfExists && _currentUserId != null)
          'user_id': _currentUserId,
        ...properties,
      }),
    );

    if (res.statusCode != 200) {
      return TetaResponse<dynamic, TetaErrorResponse>(
        data: null,
        error: TetaErrorResponse(
          code: res.statusCode,
          message: res.body,
        ),
      );
    }

    return TetaResponse<dynamic, TetaErrorResponse?>(
      data: res.body,
      error: null,
    );
  }

  /// Creates a new event
  Future<TetaResponse> get(
    final TetaAnalyticsType group,
    final String name,
    final Map<String, dynamic> properties,
  ) async {
    final uri = Uri.parse(
      '${U.analyticsUrl}events/query',
    );

    final res = await http.post(
      uri,
      headers: {
        'authorization': 'Bearer $token',
        'x-identifier': '$prjId',
      },
    );

    if (res.statusCode != 200) {
      return TetaResponse<dynamic, TetaErrorResponse>(
        data: null,
        error: TetaErrorResponse(
          code: res.statusCode,
          message: res.body,
        ),
      );
    }

    return TetaResponse<dynamic, TetaErrorResponse?>(
      data: res.body,
      error: null,
    );
  }
}
