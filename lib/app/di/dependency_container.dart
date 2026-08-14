import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/network/json_api_client.dart';
import '../../features/meeting/data/datasources/meeting_api_data_source.dart';
import '../../features/meeting/data/repositories/meeting_repository_impl.dart';
import '../../features/meeting/domain/gateways/connectivity_gateway.dart';
import '../../features/meeting/domain/gateways/meeting_media_gateway.dart';
import '../../features/meeting/domain/gateways/meeting_permission_gateway.dart';
import '../../features/meeting/domain/repositories/meeting_repository.dart';
import '../../features/meeting/domain/usecases/create_meeting.dart';
import '../../features/meeting/domain/usecases/join_meeting.dart';
import '../../features/meeting/infrastructure/connectivity/connectivity_gateway_impl.dart';
import '../../features/meeting/infrastructure/permissions/meeting_permission_gateway_factory.dart';
import '../../features/meeting/infrastructure/platform/meeting_media_gateway_factory.dart';
import '../../features/meeting/presentation/bloc/meeting_bloc.dart';

/// Registers the application's composition graph in one startup-only location.
///
/// Registered classes still declare dependencies through constructors; no
/// repository, use case, data source, BLoC, or domain class accesses GetIt.
void configureDependencies(GetIt container) {
  container
    ..registerSingleton<AppConfig>(AppConfig.fromEnvironment())
    ..registerLazySingleton<http.Client>(
      http.Client.new,
      dispose: (client) => client.close(),
    )
    ..registerLazySingleton<JsonApiClient>(
      () => HttpJsonApiClient(
        client: container<http.Client>(),
        config: container<AppConfig>(),
      ),
    )
    ..registerLazySingleton<MeetingApiDataSource>(
      () => HipsterMeetingApiDataSource(container<JsonApiClient>()),
    )
    ..registerLazySingleton<MeetingRepository>(
      () => MeetingRepositoryImpl(container<MeetingApiDataSource>()),
    )
    ..registerLazySingleton<MeetingMediaGateway>(
      createMeetingMediaGateway,
      dispose: (gateway) => gateway.dispose(),
    )
    ..registerLazySingleton<CreateMeeting>(
      () => CreateMeeting(
        container<MeetingRepository>(),
        container<MeetingMediaGateway>(),
      ),
    )
    ..registerLazySingleton<JoinMeeting>(
      () => JoinMeeting(
        container<MeetingRepository>(),
        container<MeetingMediaGateway>(),
      ),
    )
    ..registerLazySingleton<ConnectivityGateway>(ConnectivityGatewayImpl.new)
    ..registerLazySingleton<MeetingPermissionGateway>(
      createMeetingPermissionGateway,
    )
    ..registerFactory<MeetingBloc>(
      () => MeetingBloc(
        createMeeting: container<CreateMeeting>(),
        joinMeeting: container<JoinMeeting>(),
        mediaGateway: container<MeetingMediaGateway>(),
        permissionGateway: container<MeetingPermissionGateway>(),
        connectivityGateway: container<ConnectivityGateway>(),
      ),
    );
}
