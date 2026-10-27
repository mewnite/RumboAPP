// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Rumbo';

  @override
  String get appSlogan => 'Tu ciudad, en movimiento.';

  @override
  String get privacyMessage => 'Sin anuncios. Sin rastreadores.';

  @override
  String get privacyTitle => 'Privacidad y datos';

  @override
  String get privacyNetworkTitle => 'Datos que salen del dispositivo';

  @override
  String get privacyMapTitle => 'Mapa';

  @override
  String get privacyMapBody =>
      'Las solicitudes de estilos y teselas permiten al proveedor inferir la zona aproximada visible; Rumbo no adjunta tu coordenada GPS.';

  @override
  String get privacyTransitTitle => 'Transporte';

  @override
  String privacyTransitBody(String source) {
    return 'La app consulta $source para descargar el feed de transporte y, si está habilitado, posiciones de buses. No incluye tu ubicación.';
  }

  @override
  String get privacySearchTitle => 'Búsqueda de lugares en línea';

  @override
  String get privacySearchBody =>
      'Solo se envía el texto cuando activás esta opción y tocás Buscar lugares o direcciones. El proveedor ve la consulta y la IP de conexión.';

  @override
  String get privacyLiveTitle => 'Buses en vivo';

  @override
  String get privacyLiveBody =>
      'Si lo activás, Rumbo consulta el proxy configurado para actualizar posiciones mientras el mapa está visible.';

  @override
  String get privacyIpNotice =>
      'Cualquier servicio conectado recibe la dirección IP necesaria para responder. La ubicación precisa del dispositivo no se envía.';

  @override
  String get privacyLocalTitle => 'Datos que no salen del dispositivo';

  @override
  String get privacyLocalGpsTitle => 'Ubicación GPS';

  @override
  String get privacyLocalGpsBody =>
      'Se procesa localmente para centrar el mapa, buscar paradas y, durante un viaje activo iniciado por vos, calcular avisos de bajada.';

  @override
  String get privacyLocalDataTitle => 'Tus datos guardados';

  @override
  String get privacyLocalDataBody =>
      'Favoritos, Casa y Trabajo, búsquedas recientes y el origen/destino del planificador se guardan localmente. La búsqueda remota solo envía el texto tras una acción explícita.';

  @override
  String get privacyControlsTitle => 'Controles';

  @override
  String get privacyLiveSwitchTitle => 'Mostrar buses en vivo';

  @override
  String get privacyLiveSwitchDescription =>
      'Al apagarlo se detienen las consultas y se quitan los buses del mapa y los arribos.';

  @override
  String get privacyClearButton => 'Borrar mis datos locales';

  @override
  String get privacyClearConfirmTitle => '¿Borrar tus datos locales?';

  @override
  String get privacyClearConfirmBody =>
      'Se borrarán favoritos, lugares guardados, búsquedas recientes y la caché del mapa. Los datos de transporte no se borrarán.';

  @override
  String get privacyClearSuccess => 'Se borraron tus datos locales.';

  @override
  String get privacyClearFailed =>
      'No se pudieron borrar todos los datos locales.';

  @override
  String get privacyAboutTitle => 'Acerca de y atribuciones';

  @override
  String get privacyAttributionTitle => 'Datos del mapa y transporte';

  @override
  String get privacyDagTodo =>
      'TODO: confirmar el texto exacto de atribución exigido por la Licencia de Datos Abiertos – Uruguay antes de publicar.';

  @override
  String get privacyFontTitle => 'Tipografía Inter';

  @override
  String get privacyFontBody =>
      'Inter se distribuye con su licencia SIL Open Font License (OFL) y se incluye como archivo local.';

  @override
  String get privacyLicensesButton => 'Ver licencias de código abierto';

  @override
  String get privacyConfiguredSource => 'la fuente de transporte configurada';

  @override
  String get navigationMap => 'Mapa';

  @override
  String get navigationFavorites => 'Favoritos';

  @override
  String get navigationSettings => 'Ajustes';

  @override
  String get mapScreenTitle => 'Mapa';

  @override
  String get mapEmptyTitle => 'Tu ciudad te espera';

  @override
  String get mapEmptyBody =>
      'Pronto vas a poder explorar el transporte público de Montevideo.';

  @override
  String get mapSearchPlaceholder => '¿A dónde vamos?';

  @override
  String get mapSearchTitle => 'Buscar un destino';

  @override
  String get comingSoon => 'Próximamente';

  @override
  String get actionClose => 'Cerrar';

  @override
  String get actionCancel => 'Ahora no';

  @override
  String get actionRetry => 'Reintentar';

  @override
  String get mapLoading => 'Cargando el mapa';

  @override
  String get mapErrorTitle => 'No se pudo cargar el mapa';

  @override
  String get mapErrorBody => 'Revisá tu conexión e intentá de nuevo.';

  @override
  String get mapOffline =>
      'Sin conexión. Se usarán las teselas disponibles en caché.';

  @override
  String get mapAttributionButton => 'Información y atribución del mapa';

  @override
  String get mapAttributionShort => '© OSM';

  @override
  String get mapAttributionTitle => 'Datos del mapa';

  @override
  String get mapAttributionDetails =>
      'Mapa de OpenFreeMap con datos de OpenStreetMap y OpenMapTiles. La búsqueda de lugares usa OpenStreetMap/Nominatim. Las solicitudes de teselas muestran al proveedor el área aproximada que se está viendo.';

  @override
  String get mapLocationPrivacy =>
      'La ubicación precisa se procesa en este dispositivo y Rumbo no la guarda ni la envía a un servidor. Al recentrar, el proveedor puede inferir la zona aproximada por las teselas solicitadas.';

  @override
  String get nearbyBuses => 'Próximos ómnibus';

  @override
  String get mapStopsAndBuses => 'Paradas y ómnibus';

  @override
  String get mapStopsNearby => 'Paradas cercanas';

  @override
  String mapStopRouteCount(int count) {
    return '$count líneas';
  }

  @override
  String get mapStopNoRoutes => 'No hay líneas asociadas en el horario.';

  @override
  String get mapStopExpandRoutes => 'Ver variantes de línea';

  @override
  String get mapStopCollapseRoutes => 'Ocultar variantes';

  @override
  String stopDetailCode(String code) {
    return 'Código: $code';
  }

  @override
  String get stopDetailRoutes => 'Líneas que pasan';

  @override
  String get stopDetailArrivals => 'Próximos ómnibus';

  @override
  String get stopDetailOffline =>
      'Sin conexión. Los horarios disponibles pueden estar desactualizados.';

  @override
  String stopDetailError(String message) {
    return 'No se pudo cargar el detalle: $message';
  }

  @override
  String get stopDetailNoService => 'No hay servicio programado para hoy.';

  @override
  String stopArrivalEstimated(int minutes) {
    return '$minutes min · estimado';
  }

  @override
  String stopArrivalLiveEstimated(int minutes) {
    return '≈ $minutes min · en vivo, estimado';
  }

  @override
  String get stopFavoriteComingSoon => 'Favorito · Próximamente';

  @override
  String get stopHowToGetThere => 'Cómo llegar';

  @override
  String get mapNoStops =>
      'No encontramos paradas a menos de 1,5 km. Activá tu ubicación o acercá el mapa.';

  @override
  String get mapLiveSection => 'Ómnibus en vivo';

  @override
  String get mapLiveNotConfigured =>
      'El tiempo real no está conectado en esta instalación.';

  @override
  String get mapLiveLoading => 'Consultando ómnibus en vivo…';

  @override
  String get mapLiveEmpty =>
      'El STM no reporta ómnibus en vivo cerca de este punto.';

  @override
  String get mapLiveServiceDown =>
      'El servicio de ómnibus en vivo no está disponible.';

  @override
  String mapBusAge(int seconds) {
    return 'hace $seconds s';
  }

  @override
  String mapLiveError(String message) {
    return 'No se pudo actualizar el tiempo real: $message';
  }

  @override
  String mapLiveUpdated(String time) {
    return 'Recibido a las $time';
  }

  @override
  String get mapStopsLoading => 'Cargando paradas y recorridos oficiales…';

  @override
  String mapStopsError(String message) {
    return 'No se pudieron consultar las paradas: $message';
  }

  @override
  String get mapRoutesLoading => 'Buscando líneas y recorridos…';

  @override
  String mapRoutesError(String message) {
    return 'No se pudieron consultar las líneas: $message';
  }

  @override
  String get mapRouteNoVariants =>
      'No hay variantes de recorrido para esta línea.';

  @override
  String get mapRouteNoGeometry =>
      'El feed no incluye la geometría de este recorrido.';

  @override
  String get mapRouteShowOnMap => 'Ver recorrido en el mapa';

  @override
  String get mapFeedLoading => 'Descargando y preparando los datos oficiales…';

  @override
  String get mapFeedDemoOnly =>
      'La muestra de prueba no contiene recorridos reales.';

  @override
  String mapFeedError(String message) {
    return 'No se pudieron cargar los datos oficiales: $message';
  }

  @override
  String get mapFeedUnknownError =>
      'Revisá la conexión e intentá actualizar de nuevo.';

  @override
  String get mapFeedProxyHint =>
      'En debug, iniciá python tool/montevideo_api_proxy.py en la computadora. En un teléfono por USB, usá adb reverse tcp:8765 tcp:8765 y RUMBO_API_BASE_URL=http://127.0.0.1:8765.';

  @override
  String get locationRecenter => 'Usar mi ubicación';

  @override
  String get locationRationaleTitle => 'Usar tu ubicación';

  @override
  String get locationRationaleBody =>
      'Rumbo la usa para centrar el mapa. La ubicación se procesa en este dispositivo y no se guarda. El proveedor de mapas puede inferir la zona aproximada por las teselas que se solicitan.';

  @override
  String get locationRationaleContinue => 'Continuar';

  @override
  String get locationPermissionDenied =>
      'Sin permiso, el mapa sigue disponible desde Montevideo.';

  @override
  String get locationPermissionDeniedForever =>
      'El permiso está bloqueado en los ajustes del sistema.';

  @override
  String get locationServiceDisabled =>
      'Los servicios de ubicación están desactivados.';

  @override
  String get locationError =>
      'No pudimos obtener tu ubicación. Probá de nuevo.';

  @override
  String get locationRetry => 'Reintentar';

  @override
  String get locationOpenSettings => 'Abrir ajustes';

  @override
  String get locationEnableService => 'Activar ubicación';

  @override
  String get mapLogoSemanticLabel => 'Símbolo provisional de Rumbo';

  @override
  String get favoritesScreenTitle => 'Favoritos';

  @override
  String get favoritesEmptyTitle => 'Todavía no guardaste favoritos';

  @override
  String get favoritesEmptyBody =>
      'Guardá paradas o líneas desde el mapa y definí Casa y Trabajo para llegar más rápido.';

  @override
  String get favoritesLoading => 'Cargando favoritos…';

  @override
  String get favoritesLoadErrorTitle => 'No se pudieron cargar tus favoritos';

  @override
  String get favoritesLoadErrorBody =>
      'Revisá el almacenamiento del dispositivo e intentá de nuevo.';

  @override
  String get favoritesPlacesSection => 'Lugares';

  @override
  String get favoritesStopsSection => 'Paradas';

  @override
  String get favoritesLinesSection => 'Líneas';

  @override
  String get favoritesHome => 'Casa';

  @override
  String get favoritesWork => 'Trabajo';

  @override
  String get favoritesPlaceNotSet => 'Todavía sin definir';

  @override
  String get favoritesDefine => 'Definir';

  @override
  String favoritesDefinePlace(String name) {
    return 'Definir $name';
  }

  @override
  String get favoritesEmptyStops =>
      'Todavía no guardaste paradas. Abrí una parada en el mapa y tocá el corazón.';

  @override
  String get favoritesEmptyLines =>
      'Todavía no guardaste líneas. Expandí una línea en el mapa y tocá el corazón.';

  @override
  String get favoritesHelp =>
      'Deslizá para eliminar. Mantené presionado para renombrar.';

  @override
  String favoritesRemoved(String name) {
    return 'Se eliminó «$name»';
  }

  @override
  String get favoritesRenameTitle => 'Renombrar favorito';

  @override
  String get favoritesNameLabel => 'Nombre';

  @override
  String get favoritesStopSubtitle => 'Parada';

  @override
  String get favoritesLineSubtitle => 'Línea';

  @override
  String get favoritesPlaceSubtitle => 'Lugar guardado';

  @override
  String favoritesPlanTo(String name) {
    return 'Planificar viaje a $name';
  }

  @override
  String favoritesShowLineOnMap(String name) {
    return 'Ver la línea $name en el mapa';
  }

  @override
  String get stopFavoriteSave => 'Guardar parada';

  @override
  String get stopFavoriteRemove => 'Quitar de favoritos';

  @override
  String get lineFavoriteSave => 'Guardar línea';

  @override
  String get lineFavoriteRemove => 'Quitar línea de favoritos';

  @override
  String get actionSave => 'Guardar';

  @override
  String get actionUndo => 'Deshacer';

  @override
  String get settingsScreenTitle => 'Ajustes';

  @override
  String get settingsIntro => 'Personalizá Rumbo a tu gusto.';

  @override
  String get themePreferenceTitle => 'Apariencia';

  @override
  String get themePreferenceDescription => 'Elegí cómo se ve la app.';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get settingsLoadError =>
      'No se pudo cargar la preferencia de apariencia.';

  @override
  String get remotePlaceSearchTitle => 'Buscar direcciones en línea';

  @override
  String get remotePlaceSearchDescription =>
      'Al buscar, el texto escrito se envía al servicio remoto. Mientras escribís, solo se buscan datos locales.';

  @override
  String get debugThemeSample => 'Muestra de identidad visual';

  @override
  String get debugThemeSampleTitle => 'Identidad visual';

  @override
  String get debugPaletteTitle => 'Paleta Rumbo';

  @override
  String get debugTypographyTitle => 'Tipografía Inter';

  @override
  String get debugTypographyBody => 'Texto de cuerpo con escala del sistema.';

  @override
  String get debugAccentLabel => 'Acento: destino';

  @override
  String get debugErrorLabel => 'Error';

  @override
  String get debugLineChipsTitle => 'Líneas de ejemplo';

  @override
  String get debugBodyText => 'Tu ciudad. Tu camino.';

  @override
  String get debugPaletteInk => 'Ink';

  @override
  String get debugPaletteIvory => 'Ivory';

  @override
  String get debugPaletteDeepBlue => 'Deep blue';

  @override
  String get debugPaletteMint => 'Mint AA';

  @override
  String get debugPaletteLime => 'Lima de identidad';

  @override
  String get debugPaletteSurface => 'Superficie';

  @override
  String get debugPaletteDarkSurface => 'Superficie oscura';

  @override
  String get debugPaletteDarkElevated => 'Superficie elevada';

  @override
  String get transitDataTitle => 'Datos de transporte';

  @override
  String get transitDataLoading => 'Cargando datos de prueba…';

  @override
  String get transitSourceLabel => 'Fuente';

  @override
  String get transitVersionLabel => 'Versión';

  @override
  String get transitUpdatedLabel => 'Última actualización';

  @override
  String get transitValidityLabel => 'Vigencia';

  @override
  String get transitCurrent => 'Vigente';

  @override
  String get transitExpired => 'Desactualizado';

  @override
  String transitCounts(int stops, int routes) {
    return '$stops paradas · $routes líneas';
  }

  @override
  String get transitUpdateNow => 'Actualizar ahora';

  @override
  String get transitDemoNotice =>
      'Datos sintéticos para probar la app; no son datos reales del STM.';

  @override
  String get transitNoSource => 'La URL oficial del feed no está configurada.';

  @override
  String get transitAttributionLabel => 'Atribución';

  @override
  String get transitLicenseLabel => 'Licencia';

  @override
  String get transitNoData => 'No hay datos disponibles.';

  @override
  String get transitUpdatedAtNone => 'Todavía no actualizado';

  @override
  String get transitUpdateError =>
      'No se pudo actualizar; se conservan los datos guardados.';

  @override
  String get transitUnknownValue => '—';

  @override
  String get tripSearchTitle => 'Planificá tu viaje';

  @override
  String get tripOriginLabel => 'Desde';

  @override
  String get tripDestinationLabel => 'Hasta';

  @override
  String get tripOriginLocationHint => 'Mi ubicación';

  @override
  String get tripOriginStopHint => 'Elegí una parada de origen';

  @override
  String get tripDestinationHint => 'Buscá una parada';

  @override
  String get tripUseCurrentLocation => 'Usar mi ubicación';

  @override
  String get tripTimingLabel => 'Horario del viaje';

  @override
  String get tripTimingNow => 'Salir ahora';

  @override
  String get tripTimingDepartAt => 'Salir a las…';

  @override
  String get tripTimingArriveBy => 'Llegar a las…';

  @override
  String get tripTimingSummaryNow => 'Salida: ahora';

  @override
  String tripTimingSummaryDepart(String day, String time) {
    return 'Salida: $day · $time';
  }

  @override
  String tripTimingSummaryArrive(String day, String time) {
    return 'Llegada: $day · $time';
  }

  @override
  String get tripDayToday => 'Hoy';

  @override
  String get tripDayTomorrow => 'Mañana';

  @override
  String get tripPastTime => 'Esa hora ya pasó. Elegí una hora futura.';

  @override
  String get tripNoArrivalTrips => 'No hay viajes que lleguen a esa hora';

  @override
  String get tripDepartureLabel => 'Salida';

  @override
  String get tripChangeDate => 'Cambiar fecha';

  @override
  String get tripChangeTime => 'Cambiar hora';

  @override
  String get tripNoStops => 'No encontramos paradas con ese nombre.';

  @override
  String get tripNoPlaces =>
      'No encontramos lugares o direcciones con ese texto.';

  @override
  String tripSearchError(String error) {
    return 'No se pudo buscar: $error';
  }

  @override
  String get tripShowTrips => 'Buscar ómnibus';

  @override
  String get tripSearchingTrips => 'Buscando opciones…';

  @override
  String get tripLocationUnavailable =>
      'Elegí una parada de origen o activá tu ubicación desde el mapa.';

  @override
  String get tripNoTrips =>
      'No encontramos viajes con los horarios disponibles.';

  @override
  String get tripStaticScheduleNotice =>
      'Opciones basadas en horarios programados; no son arribos en vivo.';

  @override
  String get tripOfficialDataUnavailable =>
      'El GTFS oficial todavía no está disponible. Iniciá el proxy local y reintentá la actualización.';

  @override
  String get tripOriginRequired =>
      'Elegí una parada de origen o activá tu ubicación desde el mapa.';

  @override
  String get tripSearchPlaces => 'Buscar lugares o direcciones';

  @override
  String get tripPlaceResult => 'Lugar o dirección · OpenStreetMap';

  @override
  String get tripStopResult => 'Parada del STM';

  @override
  String get tripGeocodingPrivacy =>
      'Al tocar «Buscar lugares o direcciones», se envía el texto escrito al servicio remoto. La ubicación actual no se envía.';

  @override
  String get tripPlaceSearchUnavailable =>
      'La búsqueda de lugares no está configurada en esta instalación.';

  @override
  String tripPlanError(String error) {
    return 'No se pudo planificar: $error';
  }

  @override
  String get tripSortLabel => 'Ordenar por';

  @override
  String get tripSortFastest => 'Más rápido';

  @override
  String get tripSortLeastWalking => 'Menos caminata';

  @override
  String get tripSortFewestTransfers => 'Menos transbordos';

  @override
  String get tripWalkingLimitLabel => 'Caminata máxima';

  @override
  String tripWalkingMeters(int meters) {
    return '$meters m';
  }

  @override
  String tripWalkOnly(int meters) {
    return 'Caminar $meters m';
  }

  @override
  String tripPlanTimes(String departure, String arrival) {
    return '$departure–$arrival';
  }

  @override
  String tripPlanDuration(int minutes) {
    return '$minutes min';
  }

  @override
  String tripPlanWalkingMinutes(int minutes) {
    return '$minutes min de caminata';
  }

  @override
  String tripPlanTransfers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transbordos',
      one: '1 transbordo',
      zero: 'Sin transbordos',
    );
    return '$_temp0';
  }

  @override
  String get tripPlanNoLines => 'ninguna';

  @override
  String tripPlanSemantics(
    String departure,
    String arrival,
    int minutes,
    int walking,
    int transfers,
    String lines,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      transfers,
      locale: localeName,
      other: '$transfers transbordos',
      one: '1 transbordo',
      zero: 'sin transbordos',
    );
    return 'Salida $departure, llegada $arrival. $minutes min de viaje, $walking min de caminata, $_temp0. Líneas: $lines. Horarios programados.';
  }

  @override
  String get tripScheduledTimes => 'Horarios programados';

  @override
  String get tripEmptySuggestions =>
      'Probá ampliar la caminata máxima o cambiar la hora.';

  @override
  String get tripEmptyExpandWalking => 'Ampliar caminata';

  @override
  String get tripEmptyChangeTime => 'Cambiar hora';

  @override
  String get activeTripStart => 'Iniciar viaje con avisos';

  @override
  String get activeTripFinish => 'Finalizar viaje';

  @override
  String get activeTripNoTransit =>
      'Este plan no tiene tramos en ómnibus para activar avisos.';

  @override
  String get activeTripRouteUnavailable =>
      'No están disponibles las paradas de esta variante.';

  @override
  String get activeTripUnsupported =>
      'El viaje activo solo está disponible en Android y iOS.';

  @override
  String get activeTripLocationDisabled =>
      'Activá la ubicación para iniciar el seguimiento.';

  @override
  String get activeTripNotificationsRequired =>
      'Habilitá las notificaciones de Rumbo para recibir avisos de bajada.';

  @override
  String get activeTripPermissionTitle =>
      'Permiso de ubicación en segundo plano';

  @override
  String get activeTripPermissionBody =>
      'Para avisarte cuándo acercarte a bajar aunque uses otras aplicaciones, habilitá «Permitir siempre» en los ajustes. La ubicación se procesa en este dispositivo y el seguimiento se detiene al finalizar el viaje.';

  @override
  String get activeTripOpenSettings => 'Abrir ajustes';

  @override
  String get activeTripStarted =>
      'Seguimiento activo. Podés usar otras aplicaciones; Rumbo te avisará cuándo bajar.';

  @override
  String get activeTripNotificationTitle => 'Rumbo · viaje activo';

  @override
  String activeTripNotificationProgress(String stops, String stop) {
    return 'Quedan $stops paradas hasta $stop';
  }

  @override
  String activeTripStopsRemaining(int stops, String stop) {
    return 'Quedan $stops paradas hasta $stop';
  }

  @override
  String get activeTripAlertTitle => 'Próxima parada';

  @override
  String activeTripAlertBody(String stop) {
    return 'Acercate a bajar en $stop.';
  }

  @override
  String get activeTripBackgroundNotice =>
      'Rumbo está siguiendo tu viaje en este dispositivo.';

  @override
  String get tripDetailTitle => 'Tu recorrido';

  @override
  String tripDetailBetweenStops(String from, String to) {
    return '$from → $to';
  }

  @override
  String tripDetailWalkingTotal(int meters) {
    return 'Caminata total: $meters m';
  }

  @override
  String get tripDetailUnknownStop => 'Parada';

  @override
  String get tripDetailStart => 'Salida';

  @override
  String get tripDetailEnd => 'Llegada';

  @override
  String tripDetailWalkStep(int meters) {
    return 'Caminar $meters m';
  }

  @override
  String tripDetailBoard(String line, String stop) {
    return 'Tomar línea $line en $stop';
  }

  @override
  String tripDetailAlight(String stop) {
    return 'Bajar en $stop';
  }

  @override
  String tripDetailToward(String direction) {
    return 'Hacia $direction';
  }

  @override
  String tripDetailEstimatedTime(String time) {
    return '$time · estimado';
  }

  @override
  String get tripDetailWalkingApproximate =>
      'Caminata aproximada, en línea recta.';

  @override
  String get tripDetailScheduleNotice =>
      'Horarios programados, sin ETA en vivo. El trazo del ómnibus une paradas de forma esquemática y no es navegación guiada.';

  @override
  String get tripDetailChangeTrip => 'Cambiar viaje';

  @override
  String get tripDetailClose => 'Cerrar recorrido';

  @override
  String get searchHint => 'Buscá una calle, esquina, parada o lugar…';

  @override
  String get searchRecent => 'Búsquedas recientes';

  @override
  String get searchClearRecent => 'Borrar historial';

  @override
  String get searchEmptyTitle => 'Sin resultados';

  @override
  String searchEmptyBody(String query) {
    return 'No encontramos coincidencias para «$query».';
  }

  @override
  String get searchOfflineNotice =>
      'Sin conexión a internet. Mostrando solo paradas y datos locales.';

  @override
  String get searchKindStop => 'Parada de ómnibus';

  @override
  String get searchKindAddress => 'Dirección';

  @override
  String get searchKindIntersection => 'Esquina';

  @override
  String get searchKindPoi => 'Lugar de interés';

  @override
  String get searchKindNeighborhood => 'Barrio';

  @override
  String get searchKindRoute => 'Línea STM';

  @override
  String get searchKindRecent => 'Reciente';

  @override
  String get searchKindFavorite => 'Favorito';

  @override
  String lineDetailTitle(String name) {
    return 'Línea $name';
  }

  @override
  String get lineDetailVariant => 'Variante';

  @override
  String lineDetailDirection(String destination) {
    return 'Hacia $destination';
  }

  @override
  String get lineDetailStopsTitle => 'Paradas del recorrido';

  @override
  String lineDetailStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paradas',
      one: '1 parada',
    );
    return '$_temp0';
  }

  @override
  String get lineDetailUpcomingDepartures => 'Próximas salidas estimadas';

  @override
  String get lineDetailNoDepartures => 'No hay más salidas estimadas para hoy.';

  @override
  String lineDetailDepartureEstimated(String time) {
    return '$time · estimado';
  }

  @override
  String get lineDetailLiveBuses => 'Ómnibus en vivo';

  @override
  String lineDetailLiveBusesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ómnibus en circulación',
      one: '1 ómnibus en circulación',
      zero: 'Sin ómnibus en vivo en este momento',
    );
    return '$_temp0';
  }

  @override
  String get lineDetailEmpty =>
      'No hay información disponible para esta línea.';

  @override
  String get lineDetailNoVariants =>
      'No se encontraron recorridos para esta línea.';

  @override
  String lineDetailError(String message) {
    return 'No se pudo cargar el detalle de la línea: $message';
  }

  @override
  String get lineDetailOffline =>
      'Sin conexión. Los horarios y paradas mostrados son los guardados.';
}

/// The translations for Spanish Castilian, as used in Uruguay (`es_UY`).
class AppLocalizationsEsUy extends AppLocalizationsEs {
  AppLocalizationsEsUy() : super('es_UY');

  @override
  String get appTitle => 'Rumbo';

  @override
  String get appSlogan => 'Tu ciudad, en movimiento.';

  @override
  String get privacyMessage => 'Sin anuncios. Sin rastreadores.';

  @override
  String get privacyTitle => 'Privacidad y datos';

  @override
  String get privacyNetworkTitle => 'Datos que salen del dispositivo';

  @override
  String get privacyMapTitle => 'Mapa';

  @override
  String get privacyMapBody =>
      'Las solicitudes de estilos y teselas permiten al proveedor inferir la zona aproximada visible; Rumbo no adjunta tu coordenada GPS.';

  @override
  String get privacyTransitTitle => 'Transporte';

  @override
  String privacyTransitBody(String source) {
    return 'La app consulta $source para descargar el feed de transporte y, si está habilitado, posiciones de buses. No incluye tu ubicación.';
  }

  @override
  String get privacySearchTitle => 'Búsqueda de lugares en línea';

  @override
  String get privacySearchBody =>
      'Solo se envía el texto cuando activás esta opción y tocás Buscar lugares o direcciones. El proveedor ve la consulta y la IP de conexión.';

  @override
  String get privacyLiveTitle => 'Buses en vivo';

  @override
  String get privacyLiveBody =>
      'Si lo activás, Rumbo consulta el proxy configurado para actualizar posiciones mientras el mapa está visible.';

  @override
  String get privacyIpNotice =>
      'Cualquier servicio conectado recibe la dirección IP necesaria para responder. La ubicación precisa del dispositivo no se envía.';

  @override
  String get privacyLocalTitle => 'Datos que no salen del dispositivo';

  @override
  String get privacyLocalGpsTitle => 'Ubicación GPS';

  @override
  String get privacyLocalGpsBody =>
      'Se procesa localmente para centrar el mapa, buscar paradas y, durante un viaje activo iniciado por vos, calcular avisos de bajada.';

  @override
  String get privacyLocalDataTitle => 'Tus datos guardados';

  @override
  String get privacyLocalDataBody =>
      'Favoritos, Casa y Trabajo, búsquedas recientes y el origen/destino del planificador se guardan localmente. La búsqueda remota solo envía el texto tras una acción explícita.';

  @override
  String get privacyControlsTitle => 'Controles';

  @override
  String get privacyLiveSwitchTitle => 'Mostrar buses en vivo';

  @override
  String get privacyLiveSwitchDescription =>
      'Al apagarlo se detienen las consultas y se quitan los buses del mapa y los arribos.';

  @override
  String get privacyClearButton => 'Borrar mis datos locales';

  @override
  String get privacyClearConfirmTitle => '¿Borrar tus datos locales?';

  @override
  String get privacyClearConfirmBody =>
      'Se borrarán favoritos, lugares guardados, búsquedas recientes y la caché del mapa. Los datos de transporte no se borrarán.';

  @override
  String get privacyClearSuccess => 'Se borraron tus datos locales.';

  @override
  String get privacyClearFailed =>
      'No se pudieron borrar todos los datos locales.';

  @override
  String get privacyAboutTitle => 'Acerca de y atribuciones';

  @override
  String get privacyAttributionTitle => 'Datos del mapa y transporte';

  @override
  String get privacyDagTodo =>
      'TODO: confirmar el texto exacto de atribución exigido por la Licencia de Datos Abiertos – Uruguay antes de publicar.';

  @override
  String get privacyFontTitle => 'Tipografía Inter';

  @override
  String get privacyFontBody =>
      'Inter se distribuye con su licencia SIL Open Font License (OFL) y se incluye como archivo local.';

  @override
  String get privacyLicensesButton => 'Ver licencias de código abierto';

  @override
  String get privacyConfiguredSource => 'la fuente de transporte configurada';

  @override
  String get navigationMap => 'Mapa';

  @override
  String get navigationFavorites => 'Favoritos';

  @override
  String get navigationSettings => 'Ajustes';

  @override
  String get mapScreenTitle => 'Mapa';

  @override
  String get mapEmptyTitle => 'Tu ciudad te espera';

  @override
  String get mapEmptyBody =>
      'Pronto vas a poder explorar el transporte público de Montevideo.';

  @override
  String get mapSearchPlaceholder => '¿A dónde vamos?';

  @override
  String get mapSearchTitle => 'Buscar un destino';

  @override
  String get comingSoon => 'Próximamente';

  @override
  String get actionClose => 'Cerrar';

  @override
  String get actionCancel => 'Ahora no';

  @override
  String get actionRetry => 'Reintentar';

  @override
  String get mapLoading => 'Cargando el mapa';

  @override
  String get mapErrorTitle => 'No se pudo cargar el mapa';

  @override
  String get mapErrorBody => 'Revisá tu conexión e intentá de nuevo.';

  @override
  String get mapOffline =>
      'Sin conexión. Se usarán las teselas disponibles en caché.';

  @override
  String get mapAttributionButton => 'Información y atribución del mapa';

  @override
  String get mapAttributionShort => '© OSM';

  @override
  String get mapAttributionTitle => 'Datos del mapa';

  @override
  String get mapAttributionDetails =>
      'Mapa de OpenFreeMap con datos de OpenStreetMap y OpenMapTiles. La búsqueda de lugares usa OpenStreetMap/Nominatim. Las solicitudes de teselas muestran al proveedor el área aproximada que se está viendo.';

  @override
  String get mapLocationPrivacy =>
      'La ubicación precisa se procesa en este dispositivo y Rumbo no la guarda ni la envía a un servidor. Al recentrar, el proveedor puede inferir la zona aproximada por las teselas solicitadas.';

  @override
  String get nearbyBuses => 'Próximos ómnibus';

  @override
  String get mapStopsAndBuses => 'Paradas y ómnibus';

  @override
  String get mapStopsNearby => 'Paradas cercanas';

  @override
  String mapStopRouteCount(int count) {
    return '$count líneas';
  }

  @override
  String get mapStopNoRoutes => 'No hay líneas asociadas en el horario.';

  @override
  String get mapStopExpandRoutes => 'Ver variantes de línea';

  @override
  String get mapStopCollapseRoutes => 'Ocultar variantes';

  @override
  String stopDetailCode(String code) {
    return 'Código: $code';
  }

  @override
  String get stopDetailRoutes => 'Líneas que pasan';

  @override
  String get stopDetailArrivals => 'Próximos ómnibus';

  @override
  String get stopDetailOffline =>
      'Sin conexión. Los horarios disponibles pueden estar desactualizados.';

  @override
  String stopDetailError(String message) {
    return 'No se pudo cargar el detalle: $message';
  }

  @override
  String get stopDetailNoService => 'No hay servicio programado para hoy.';

  @override
  String stopArrivalEstimated(int minutes) {
    return '$minutes min · estimado';
  }

  @override
  String stopArrivalLiveEstimated(int minutes) {
    return '≈ $minutes min · en vivo, estimado';
  }

  @override
  String get stopFavoriteComingSoon => 'Favorito · Próximamente';

  @override
  String get stopHowToGetThere => 'Cómo llegar';

  @override
  String get mapNoStops =>
      'No encontramos paradas a menos de 1,5 km. Activá tu ubicación o acercá el mapa.';

  @override
  String get mapLiveSection => 'Ómnibus en vivo';

  @override
  String get mapLiveNotConfigured =>
      'El tiempo real no está conectado en esta instalación.';

  @override
  String get mapLiveLoading => 'Consultando ómnibus en vivo…';

  @override
  String get mapLiveEmpty =>
      'El STM no reporta ómnibus en vivo cerca de este punto.';

  @override
  String get mapLiveServiceDown =>
      'El servicio de ómnibus en vivo no está disponible.';

  @override
  String mapBusAge(int seconds) {
    return 'hace $seconds s';
  }

  @override
  String mapLiveError(String message) {
    return 'No se pudo actualizar el tiempo real: $message';
  }

  @override
  String mapLiveUpdated(String time) {
    return 'Recibido a las $time';
  }

  @override
  String get mapStopsLoading => 'Cargando paradas y recorridos oficiales…';

  @override
  String mapStopsError(String message) {
    return 'No se pudieron consultar las paradas: $message';
  }

  @override
  String get mapRoutesLoading => 'Buscando líneas y recorridos…';

  @override
  String mapRoutesError(String message) {
    return 'No se pudieron consultar las líneas: $message';
  }

  @override
  String get mapRouteNoVariants =>
      'No hay variantes de recorrido para esta línea.';

  @override
  String get mapRouteNoGeometry =>
      'El feed no incluye la geometría de este recorrido.';

  @override
  String get mapRouteShowOnMap => 'Ver recorrido en el mapa';

  @override
  String get mapFeedLoading => 'Descargando y preparando los datos oficiales…';

  @override
  String get mapFeedDemoOnly =>
      'La muestra de prueba no contiene recorridos reales.';

  @override
  String mapFeedError(String message) {
    return 'No se pudieron cargar los datos oficiales: $message';
  }

  @override
  String get mapFeedUnknownError =>
      'Revisá la conexión e intentá actualizar de nuevo.';

  @override
  String get mapFeedProxyHint =>
      'En debug, iniciá python tool/montevideo_api_proxy.py en la computadora. En un teléfono por USB, usá adb reverse tcp:8765 tcp:8765 y RUMBO_API_BASE_URL=http://127.0.0.1:8765.';

  @override
  String get locationRecenter => 'Usar mi ubicación';

  @override
  String get locationRationaleTitle => 'Usar tu ubicación';

  @override
  String get locationRationaleBody =>
      'Rumbo la usa para centrar el mapa. La ubicación se procesa en este dispositivo y no se guarda. El proveedor de mapas puede inferir la zona aproximada por las teselas que se solicitan.';

  @override
  String get locationRationaleContinue => 'Continuar';

  @override
  String get locationPermissionDenied =>
      'Sin permiso, el mapa sigue disponible desde Montevideo.';

  @override
  String get locationPermissionDeniedForever =>
      'El permiso está bloqueado en los ajustes del sistema.';

  @override
  String get locationServiceDisabled =>
      'Los servicios de ubicación están desactivados.';

  @override
  String get locationError =>
      'No pudimos obtener tu ubicación. Probá de nuevo.';

  @override
  String get locationRetry => 'Reintentar';

  @override
  String get locationOpenSettings => 'Abrir ajustes';

  @override
  String get locationEnableService => 'Activar ubicación';

  @override
  String get mapLogoSemanticLabel => 'Símbolo provisional de Rumbo';

  @override
  String get favoritesScreenTitle => 'Favoritos';

  @override
  String get favoritesEmptyTitle => 'Todavía no guardaste favoritos';

  @override
  String get favoritesEmptyBody =>
      'Guardá paradas o líneas desde el mapa y definí Casa y Trabajo para llegar más rápido.';

  @override
  String get favoritesLoading => 'Cargando favoritos…';

  @override
  String get favoritesLoadErrorTitle => 'No se pudieron cargar tus favoritos';

  @override
  String get favoritesLoadErrorBody =>
      'Revisá el almacenamiento del dispositivo e intentá de nuevo.';

  @override
  String get favoritesPlacesSection => 'Lugares';

  @override
  String get favoritesStopsSection => 'Paradas';

  @override
  String get favoritesLinesSection => 'Líneas';

  @override
  String get favoritesHome => 'Casa';

  @override
  String get favoritesWork => 'Trabajo';

  @override
  String get favoritesPlaceNotSet => 'Todavía sin definir';

  @override
  String get favoritesDefine => 'Definir';

  @override
  String favoritesDefinePlace(String name) {
    return 'Definir $name';
  }

  @override
  String get favoritesEmptyStops =>
      'Todavía no guardaste paradas. Abrí una parada en el mapa y tocá el corazón.';

  @override
  String get favoritesEmptyLines =>
      'Todavía no guardaste líneas. Expandí una línea en el mapa y tocá el corazón.';

  @override
  String get favoritesHelp =>
      'Deslizá para eliminar. Mantené presionado para renombrar.';

  @override
  String favoritesRemoved(String name) {
    return 'Se eliminó «$name»';
  }

  @override
  String get favoritesRenameTitle => 'Renombrar favorito';

  @override
  String get favoritesNameLabel => 'Nombre';

  @override
  String get favoritesStopSubtitle => 'Parada';

  @override
  String get favoritesLineSubtitle => 'Línea';

  @override
  String get favoritesPlaceSubtitle => 'Lugar guardado';

  @override
  String favoritesPlanTo(String name) {
    return 'Planificar viaje a $name';
  }

  @override
  String favoritesShowLineOnMap(String name) {
    return 'Ver la línea $name en el mapa';
  }

  @override
  String get stopFavoriteSave => 'Guardar parada';

  @override
  String get stopFavoriteRemove => 'Quitar de favoritos';

  @override
  String get lineFavoriteSave => 'Guardar línea';

  @override
  String get lineFavoriteRemove => 'Quitar línea de favoritos';

  @override
  String get actionSave => 'Guardar';

  @override
  String get actionUndo => 'Deshacer';

  @override
  String get settingsScreenTitle => 'Ajustes';

  @override
  String get settingsIntro => 'Personalizá Rumbo a tu gusto.';

  @override
  String get themePreferenceTitle => 'Apariencia';

  @override
  String get themePreferenceDescription => 'Elegí cómo se ve la app.';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get settingsLoadError =>
      'No se pudo cargar la preferencia de apariencia.';

  @override
  String get remotePlaceSearchTitle => 'Buscar direcciones en línea';

  @override
  String get remotePlaceSearchDescription =>
      'Al buscar, el texto escrito se envía al servicio remoto. Mientras escribís, solo se buscan datos locales.';

  @override
  String get debugThemeSample => 'Muestra de identidad visual';

  @override
  String get debugThemeSampleTitle => 'Identidad visual';

  @override
  String get debugPaletteTitle => 'Paleta Rumbo';

  @override
  String get debugTypographyTitle => 'Tipografía Inter';

  @override
  String get debugTypographyBody => 'Texto de cuerpo con escala del sistema.';

  @override
  String get debugAccentLabel => 'Acento: destino';

  @override
  String get debugErrorLabel => 'Error';

  @override
  String get debugLineChipsTitle => 'Líneas de ejemplo';

  @override
  String get debugBodyText => 'Tu ciudad. Tu camino.';

  @override
  String get debugPaletteInk => 'Ink';

  @override
  String get debugPaletteIvory => 'Ivory';

  @override
  String get debugPaletteDeepBlue => 'Deep blue';

  @override
  String get debugPaletteMint => 'Mint AA';

  @override
  String get debugPaletteLime => 'Lima de identidad';

  @override
  String get debugPaletteSurface => 'Superficie';

  @override
  String get debugPaletteDarkSurface => 'Superficie oscura';

  @override
  String get debugPaletteDarkElevated => 'Superficie elevada';

  @override
  String get transitDataTitle => 'Datos de transporte';

  @override
  String get transitDataLoading => 'Cargando datos de prueba…';

  @override
  String get transitSourceLabel => 'Fuente';

  @override
  String get transitVersionLabel => 'Versión';

  @override
  String get transitUpdatedLabel => 'Última actualización';

  @override
  String get transitValidityLabel => 'Vigencia';

  @override
  String get transitCurrent => 'Vigente';

  @override
  String get transitExpired => 'Desactualizado';

  @override
  String transitCounts(int stops, int routes) {
    return '$stops paradas · $routes líneas';
  }

  @override
  String get transitUpdateNow => 'Actualizar ahora';

  @override
  String get transitDemoNotice =>
      'Datos sintéticos para probar la app; no son datos reales del STM.';

  @override
  String get transitNoSource => 'La URL oficial del feed no está configurada.';

  @override
  String get transitAttributionLabel => 'Atribución';

  @override
  String get transitLicenseLabel => 'Licencia';

  @override
  String get transitNoData => 'No hay datos disponibles.';

  @override
  String get transitUpdatedAtNone => 'Todavía no actualizado';

  @override
  String get transitUpdateError =>
      'No se pudo actualizar; se conservan los datos guardados.';

  @override
  String get transitUnknownValue => '—';

  @override
  String get tripSearchTitle => 'Planificá tu viaje';

  @override
  String get tripOriginLabel => 'Desde';

  @override
  String get tripDestinationLabel => 'Hasta';

  @override
  String get tripOriginLocationHint => 'Mi ubicación';

  @override
  String get tripOriginStopHint => 'Elegí una parada de origen';

  @override
  String get tripDestinationHint => 'Buscá una parada';

  @override
  String get tripUseCurrentLocation => 'Usar mi ubicación';

  @override
  String get tripTimingLabel => 'Horario del viaje';

  @override
  String get tripTimingNow => 'Salir ahora';

  @override
  String get tripTimingDepartAt => 'Salir a las…';

  @override
  String get tripTimingArriveBy => 'Llegar a las…';

  @override
  String get tripTimingSummaryNow => 'Salida: ahora';

  @override
  String tripTimingSummaryDepart(String day, String time) {
    return 'Salida: $day · $time';
  }

  @override
  String tripTimingSummaryArrive(String day, String time) {
    return 'Llegada: $day · $time';
  }

  @override
  String get tripDayToday => 'Hoy';

  @override
  String get tripDayTomorrow => 'Mañana';

  @override
  String get tripPastTime => 'Esa hora ya pasó. Elegí una hora futura.';

  @override
  String get tripNoArrivalTrips => 'No hay viajes que lleguen a esa hora';

  @override
  String get tripDepartureLabel => 'Salida';

  @override
  String get tripChangeDate => 'Cambiar fecha';

  @override
  String get tripChangeTime => 'Cambiar hora';

  @override
  String get tripNoStops => 'No encontramos paradas con ese nombre.';

  @override
  String get tripNoPlaces =>
      'No encontramos lugares o direcciones con ese texto.';

  @override
  String tripSearchError(String error) {
    return 'No se pudo buscar: $error';
  }

  @override
  String get tripShowTrips => 'Buscar ómnibus';

  @override
  String get tripSearchingTrips => 'Buscando opciones…';

  @override
  String get tripLocationUnavailable =>
      'Elegí una parada de origen o activá tu ubicación desde el mapa.';

  @override
  String get tripNoTrips =>
      'No encontramos viajes con los horarios disponibles.';

  @override
  String get tripStaticScheduleNotice =>
      'Opciones basadas en horarios programados; no son arribos en vivo.';

  @override
  String get tripOfficialDataUnavailable =>
      'El GTFS oficial todavía no está disponible. Iniciá el proxy local y reintentá la actualización.';

  @override
  String get tripOriginRequired =>
      'Elegí una parada de origen o activá tu ubicación desde el mapa.';

  @override
  String get tripSearchPlaces => 'Buscar lugares o direcciones';

  @override
  String get tripPlaceResult => 'Lugar o dirección · OpenStreetMap';

  @override
  String get tripStopResult => 'Parada del STM';

  @override
  String get tripGeocodingPrivacy =>
      'Al tocar «Buscar lugares o direcciones», se envía el texto escrito al servicio remoto. La ubicación actual no se envía.';

  @override
  String get tripPlaceSearchUnavailable =>
      'La búsqueda de lugares no está configurada en esta instalación.';

  @override
  String tripPlanError(String error) {
    return 'No se pudo planificar: $error';
  }

  @override
  String get tripSortLabel => 'Ordenar por';

  @override
  String get tripSortFastest => 'Más rápido';

  @override
  String get tripSortLeastWalking => 'Menos caminata';

  @override
  String get tripSortFewestTransfers => 'Menos transbordos';

  @override
  String get tripWalkingLimitLabel => 'Caminata máxima';

  @override
  String tripWalkingMeters(int meters) {
    return '$meters m';
  }

  @override
  String tripWalkOnly(int meters) {
    return 'Caminar $meters m';
  }

  @override
  String tripPlanTimes(String departure, String arrival) {
    return '$departure–$arrival';
  }

  @override
  String tripPlanDuration(int minutes) {
    return '$minutes min';
  }

  @override
  String tripPlanWalkingMinutes(int minutes) {
    return '$minutes min de caminata';
  }

  @override
  String tripPlanTransfers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transbordos',
      one: '1 transbordo',
      zero: 'Sin transbordos',
    );
    return '$_temp0';
  }

  @override
  String get tripPlanNoLines => 'ninguna';

  @override
  String tripPlanSemantics(
    String departure,
    String arrival,
    int minutes,
    int walking,
    int transfers,
    String lines,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      transfers,
      locale: localeName,
      other: '$transfers transbordos',
      one: '1 transbordo',
      zero: 'sin transbordos',
    );
    return 'Salida $departure, llegada $arrival. $minutes min de viaje, $walking min de caminata, $_temp0. Líneas: $lines. Horarios programados.';
  }

  @override
  String get tripScheduledTimes => 'Horarios programados';

  @override
  String get tripEmptySuggestions =>
      'Probá ampliar la caminata máxima o cambiar la hora.';

  @override
  String get tripEmptyExpandWalking => 'Ampliar caminata';

  @override
  String get tripEmptyChangeTime => 'Cambiar hora';

  @override
  String get activeTripStart => 'Iniciar viaje con avisos';

  @override
  String get activeTripFinish => 'Finalizar viaje';

  @override
  String get activeTripNoTransit =>
      'Este plan no tiene tramos en ómnibus para activar avisos.';

  @override
  String get activeTripRouteUnavailable =>
      'No están disponibles las paradas de esta variante.';

  @override
  String get activeTripUnsupported =>
      'El viaje activo solo está disponible en Android y iOS.';

  @override
  String get activeTripLocationDisabled =>
      'Activá la ubicación para iniciar el seguimiento.';

  @override
  String get activeTripNotificationsRequired =>
      'Habilitá las notificaciones de Rumbo para recibir avisos de bajada.';

  @override
  String get activeTripPermissionTitle =>
      'Permiso de ubicación en segundo plano';

  @override
  String get activeTripPermissionBody =>
      'Para avisarte cuándo acercarte a bajar aunque uses otras aplicaciones, habilitá «Permitir siempre» en los ajustes. La ubicación se procesa en este dispositivo y el seguimiento se detiene al finalizar el viaje.';

  @override
  String get activeTripOpenSettings => 'Abrir ajustes';

  @override
  String get activeTripStarted =>
      'Seguimiento activo. Podés usar otras aplicaciones; Rumbo te avisará cuándo bajar.';

  @override
  String get activeTripNotificationTitle => 'Rumbo · viaje activo';

  @override
  String activeTripNotificationProgress(String stops, String stop) {
    return 'Quedan $stops paradas hasta $stop';
  }

  @override
  String activeTripStopsRemaining(int stops, String stop) {
    return 'Quedan $stops paradas hasta $stop';
  }

  @override
  String get activeTripAlertTitle => 'Próxima parada';

  @override
  String activeTripAlertBody(String stop) {
    return 'Acercate a bajar en $stop.';
  }

  @override
  String get activeTripBackgroundNotice =>
      'Rumbo está siguiendo tu viaje en este dispositivo.';

  @override
  String get tripDetailTitle => 'Tu recorrido';

  @override
  String tripDetailBetweenStops(String from, String to) {
    return '$from → $to';
  }

  @override
  String tripDetailWalkingTotal(int meters) {
    return 'Caminata total: $meters m';
  }

  @override
  String get tripDetailUnknownStop => 'Parada';

  @override
  String get tripDetailStart => 'Salida';

  @override
  String get tripDetailEnd => 'Llegada';

  @override
  String tripDetailWalkStep(int meters) {
    return 'Caminar $meters m';
  }

  @override
  String tripDetailBoard(String line, String stop) {
    return 'Tomar línea $line en $stop';
  }

  @override
  String tripDetailAlight(String stop) {
    return 'Bajar en $stop';
  }

  @override
  String tripDetailToward(String direction) {
    return 'Hacia $direction';
  }

  @override
  String tripDetailEstimatedTime(String time) {
    return '$time · estimado';
  }

  @override
  String get tripDetailWalkingApproximate =>
      'Caminata aproximada, en línea recta.';

  @override
  String get tripDetailScheduleNotice =>
      'Horarios programados, sin ETA en vivo. El trazo del ómnibus une paradas de forma esquemática y no es navegación guiada.';

  @override
  String get tripDetailChangeTrip => 'Cambiar viaje';

  @override
  String get tripDetailClose => 'Cerrar recorrido';

  @override
  String get searchHint => 'Buscá una calle, esquina, parada o lugar…';

  @override
  String get searchRecent => 'Búsquedas recientes';

  @override
  String get searchClearRecent => 'Borrar historial';

  @override
  String get searchEmptyTitle => 'Sin resultados';

  @override
  String searchEmptyBody(String query) {
    return 'No encontramos coincidencias para «$query».';
  }

  @override
  String get searchOfflineNotice =>
      'Sin conexión a internet. Mostrando solo paradas y datos locales.';

  @override
  String get searchKindStop => 'Parada de ómnibus';

  @override
  String get searchKindAddress => 'Dirección';

  @override
  String get searchKindIntersection => 'Esquina';

  @override
  String get searchKindPoi => 'Lugar de interés';

  @override
  String get searchKindNeighborhood => 'Barrio';

  @override
  String get searchKindRoute => 'Línea STM';

  @override
  String get searchKindRecent => 'Reciente';

  @override
  String get searchKindFavorite => 'Favorito';

  @override
  String lineDetailTitle(String name) {
    return 'Línea $name';
  }

  @override
  String get lineDetailVariant => 'Variante';

  @override
  String lineDetailDirection(String destination) {
    return 'Hacia $destination';
  }

  @override
  String get lineDetailStopsTitle => 'Paradas del recorrido';

  @override
  String lineDetailStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paradas',
      one: '1 parada',
    );
    return '$_temp0';
  }

  @override
  String get lineDetailUpcomingDepartures => 'Próximas salidas estimadas';

  @override
  String get lineDetailNoDepartures => 'No hay más salidas estimadas para hoy.';

  @override
  String lineDetailDepartureEstimated(String time) {
    return '$time · estimado';
  }

  @override
  String get lineDetailLiveBuses => 'Ómnibus en vivo';

  @override
  String lineDetailLiveBusesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ómnibus en circulación',
      one: '1 ómnibus en circulación',
      zero: 'Sin ómnibus en vivo en este momento',
    );
    return '$_temp0';
  }

  @override
  String get lineDetailEmpty =>
      'No hay información disponible para esta línea.';

  @override
  String get lineDetailNoVariants =>
      'No se encontraron recorridos para esta línea.';

  @override
  String lineDetailError(String message) {
    return 'No se pudo cargar el detalle de la línea: $message';
  }

  @override
  String get lineDetailOffline =>
      'Sin conexión. Los horarios y paradas mostrados son los guardados.';
}
