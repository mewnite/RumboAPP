import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('es', 'UY'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Rumbo'**
  String get appTitle;

  /// No description provided for @appSlogan.
  ///
  /// In es_UY, this message translates to:
  /// **'Tu ciudad, en movimiento.'**
  String get appSlogan;

  /// No description provided for @privacyMessage.
  ///
  /// In es_UY, this message translates to:
  /// **'Sin anuncios. Sin rastreadores.'**
  String get privacyMessage;

  /// No description provided for @privacyTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Privacidad y datos'**
  String get privacyTitle;

  /// No description provided for @privacyNetworkTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Datos que salen del dispositivo'**
  String get privacyNetworkTitle;

  /// No description provided for @privacyMapTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Mapa'**
  String get privacyMapTitle;

  /// No description provided for @privacyMapBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Las solicitudes de estilos y teselas permiten al proveedor inferir la zona aproximada visible; Rumbo no adjunta tu coordenada GPS.'**
  String get privacyMapBody;

  /// No description provided for @privacyTransitTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Transporte'**
  String get privacyTransitTitle;

  /// No description provided for @privacyTransitBody.
  ///
  /// In es_UY, this message translates to:
  /// **'La app consulta {source} para descargar el feed de transporte y, si está habilitado, posiciones de buses. No incluye tu ubicación.'**
  String privacyTransitBody(String source);

  /// No description provided for @privacySearchTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Búsqueda de lugares en línea'**
  String get privacySearchTitle;

  /// No description provided for @privacySearchBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Solo se envía el texto cuando activás esta opción y tocás Buscar lugares o direcciones. El proveedor ve la consulta y la IP de conexión.'**
  String get privacySearchBody;

  /// No description provided for @privacyLiveTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Buses en vivo'**
  String get privacyLiveTitle;

  /// No description provided for @privacyLiveBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Si lo activás, Rumbo consulta el proxy configurado para actualizar posiciones mientras el mapa está visible.'**
  String get privacyLiveBody;

  /// No description provided for @privacyIpNotice.
  ///
  /// In es_UY, this message translates to:
  /// **'Cualquier servicio conectado recibe la dirección IP necesaria para responder. La ubicación precisa del dispositivo no se envía.'**
  String get privacyIpNotice;

  /// No description provided for @privacyLocalTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Datos que no salen del dispositivo'**
  String get privacyLocalTitle;

  /// No description provided for @privacyLocalGpsTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Ubicación GPS'**
  String get privacyLocalGpsTitle;

  /// No description provided for @privacyLocalGpsBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Se procesa localmente para centrar el mapa, buscar paradas y, durante un viaje activo iniciado por vos, calcular avisos de bajada.'**
  String get privacyLocalGpsBody;

  /// No description provided for @privacyLocalDataTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Tus datos guardados'**
  String get privacyLocalDataTitle;

  /// No description provided for @privacyLocalDataBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Favoritos, Casa y Trabajo, búsquedas recientes y el origen/destino del planificador se guardan localmente. La búsqueda remota solo envía el texto tras una acción explícita.'**
  String get privacyLocalDataBody;

  /// No description provided for @privacyControlsTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Controles'**
  String get privacyControlsTitle;

  /// No description provided for @privacyLiveSwitchTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Mostrar buses en vivo'**
  String get privacyLiveSwitchTitle;

  /// No description provided for @privacyLiveSwitchDescription.
  ///
  /// In es_UY, this message translates to:
  /// **'Al apagarlo se detienen las consultas y se quitan los buses del mapa y los arribos.'**
  String get privacyLiveSwitchDescription;

  /// No description provided for @privacyClearButton.
  ///
  /// In es_UY, this message translates to:
  /// **'Borrar mis datos locales'**
  String get privacyClearButton;

  /// No description provided for @privacyClearConfirmTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'¿Borrar tus datos locales?'**
  String get privacyClearConfirmTitle;

  /// No description provided for @privacyClearConfirmBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Se borrarán favoritos, lugares guardados, búsquedas recientes y la caché del mapa. Los datos de transporte no se borrarán.'**
  String get privacyClearConfirmBody;

  /// No description provided for @privacyClearSuccess.
  ///
  /// In es_UY, this message translates to:
  /// **'Se borraron tus datos locales.'**
  String get privacyClearSuccess;

  /// No description provided for @privacyClearFailed.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudieron borrar todos los datos locales.'**
  String get privacyClearFailed;

  /// No description provided for @privacyAboutTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Acerca de y atribuciones'**
  String get privacyAboutTitle;

  /// No description provided for @privacyAttributionTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Datos del mapa y transporte'**
  String get privacyAttributionTitle;

  /// No description provided for @privacyDagTodo.
  ///
  /// In es_UY, this message translates to:
  /// **'TODO: confirmar el texto exacto de atribución exigido por la Licencia de Datos Abiertos – Uruguay antes de publicar.'**
  String get privacyDagTodo;

  /// No description provided for @privacyFontTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Tipografía Inter'**
  String get privacyFontTitle;

  /// No description provided for @privacyFontBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Inter se distribuye con su licencia SIL Open Font License (OFL) y se incluye como archivo local.'**
  String get privacyFontBody;

  /// No description provided for @privacyLicensesButton.
  ///
  /// In es_UY, this message translates to:
  /// **'Ver licencias de código abierto'**
  String get privacyLicensesButton;

  /// No description provided for @privacyConfiguredSource.
  ///
  /// In es_UY, this message translates to:
  /// **'la fuente de transporte configurada'**
  String get privacyConfiguredSource;

  /// No description provided for @navigationMap.
  ///
  /// In es_UY, this message translates to:
  /// **'Mapa'**
  String get navigationMap;

  /// No description provided for @navigationFavorites.
  ///
  /// In es_UY, this message translates to:
  /// **'Favoritos'**
  String get navigationFavorites;

  /// No description provided for @navigationSettings.
  ///
  /// In es_UY, this message translates to:
  /// **'Ajustes'**
  String get navigationSettings;

  /// No description provided for @mapScreenTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Mapa'**
  String get mapScreenTitle;

  /// No description provided for @mapEmptyTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Tu ciudad te espera'**
  String get mapEmptyTitle;

  /// No description provided for @mapEmptyBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Pronto vas a poder explorar el transporte público de Montevideo.'**
  String get mapEmptyBody;

  /// No description provided for @mapSearchPlaceholder.
  ///
  /// In es_UY, this message translates to:
  /// **'¿A dónde vamos?'**
  String get mapSearchPlaceholder;

  /// No description provided for @mapSearchTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscar un destino'**
  String get mapSearchTitle;

  /// No description provided for @comingSoon.
  ///
  /// In es_UY, this message translates to:
  /// **'Próximamente'**
  String get comingSoon;

  /// No description provided for @actionClose.
  ///
  /// In es_UY, this message translates to:
  /// **'Cerrar'**
  String get actionClose;

  /// No description provided for @actionCancel.
  ///
  /// In es_UY, this message translates to:
  /// **'Ahora no'**
  String get actionCancel;

  /// No description provided for @actionRetry.
  ///
  /// In es_UY, this message translates to:
  /// **'Reintentar'**
  String get actionRetry;

  /// No description provided for @mapLoading.
  ///
  /// In es_UY, this message translates to:
  /// **'Cargando el mapa'**
  String get mapLoading;

  /// No description provided for @mapErrorTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo cargar el mapa'**
  String get mapErrorTitle;

  /// No description provided for @mapErrorBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Revisá tu conexión e intentá de nuevo.'**
  String get mapErrorBody;

  /// No description provided for @mapOffline.
  ///
  /// In es_UY, this message translates to:
  /// **'Sin conexión. Se usarán las teselas disponibles en caché.'**
  String get mapOffline;

  /// No description provided for @mapAttributionButton.
  ///
  /// In es_UY, this message translates to:
  /// **'Información y atribución del mapa'**
  String get mapAttributionButton;

  /// No description provided for @mapAttributionShort.
  ///
  /// In es_UY, this message translates to:
  /// **'© OSM'**
  String get mapAttributionShort;

  /// No description provided for @mapAttributionTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Datos del mapa'**
  String get mapAttributionTitle;

  /// No description provided for @mapAttributionDetails.
  ///
  /// In es_UY, this message translates to:
  /// **'Mapa de OpenFreeMap con datos de OpenStreetMap y OpenMapTiles. La búsqueda de lugares usa OpenStreetMap/Nominatim. Las solicitudes de teselas muestran al proveedor el área aproximada que se está viendo.'**
  String get mapAttributionDetails;

  /// No description provided for @mapLocationPrivacy.
  ///
  /// In es_UY, this message translates to:
  /// **'La ubicación precisa se procesa en este dispositivo y Rumbo no la guarda ni la envía a un servidor. Al recentrar, el proveedor puede inferir la zona aproximada por las teselas solicitadas.'**
  String get mapLocationPrivacy;

  /// No description provided for @nearbyBuses.
  ///
  /// In es_UY, this message translates to:
  /// **'Próximos ómnibus'**
  String get nearbyBuses;

  /// No description provided for @mapStopsAndBuses.
  ///
  /// In es_UY, this message translates to:
  /// **'Paradas y ómnibus'**
  String get mapStopsAndBuses;

  /// No description provided for @mapStopsNearby.
  ///
  /// In es_UY, this message translates to:
  /// **'Paradas cercanas'**
  String get mapStopsNearby;

  /// No description provided for @mapStopRouteCount.
  ///
  /// In es_UY, this message translates to:
  /// **'{count} líneas'**
  String mapStopRouteCount(int count);

  /// No description provided for @mapStopNoRoutes.
  ///
  /// In es_UY, this message translates to:
  /// **'No hay líneas asociadas en el horario.'**
  String get mapStopNoRoutes;

  /// No description provided for @mapStopExpandRoutes.
  ///
  /// In es_UY, this message translates to:
  /// **'Ver variantes de línea'**
  String get mapStopExpandRoutes;

  /// No description provided for @mapStopCollapseRoutes.
  ///
  /// In es_UY, this message translates to:
  /// **'Ocultar variantes'**
  String get mapStopCollapseRoutes;

  /// No description provided for @stopDetailCode.
  ///
  /// In es_UY, this message translates to:
  /// **'Código: {code}'**
  String stopDetailCode(String code);

  /// No description provided for @stopDetailRoutes.
  ///
  /// In es_UY, this message translates to:
  /// **'Líneas que pasan'**
  String get stopDetailRoutes;

  /// No description provided for @stopDetailArrivals.
  ///
  /// In es_UY, this message translates to:
  /// **'Próximos ómnibus'**
  String get stopDetailArrivals;

  /// No description provided for @stopDetailOffline.
  ///
  /// In es_UY, this message translates to:
  /// **'Sin conexión. Los horarios disponibles pueden estar desactualizados.'**
  String get stopDetailOffline;

  /// No description provided for @stopDetailError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo cargar el detalle: {message}'**
  String stopDetailError(String message);

  /// No description provided for @stopDetailNoService.
  ///
  /// In es_UY, this message translates to:
  /// **'No hay servicio programado para hoy.'**
  String get stopDetailNoService;

  /// No description provided for @stopArrivalEstimated.
  ///
  /// In es_UY, this message translates to:
  /// **'{minutes} min · estimado'**
  String stopArrivalEstimated(int minutes);

  /// No description provided for @stopArrivalLiveEstimated.
  ///
  /// In es_UY, this message translates to:
  /// **'≈ {minutes} min · en vivo, estimado'**
  String stopArrivalLiveEstimated(int minutes);

  /// No description provided for @stopFavoriteComingSoon.
  ///
  /// In es_UY, this message translates to:
  /// **'Favorito · Próximamente'**
  String get stopFavoriteComingSoon;

  /// No description provided for @stopHowToGetThere.
  ///
  /// In es_UY, this message translates to:
  /// **'Cómo llegar'**
  String get stopHowToGetThere;

  /// No description provided for @mapNoStops.
  ///
  /// In es_UY, this message translates to:
  /// **'No encontramos paradas a menos de 1,5 km. Activá tu ubicación o acercá el mapa.'**
  String get mapNoStops;

  /// No description provided for @mapLiveSection.
  ///
  /// In es_UY, this message translates to:
  /// **'Ómnibus en vivo'**
  String get mapLiveSection;

  /// No description provided for @mapLiveNotConfigured.
  ///
  /// In es_UY, this message translates to:
  /// **'El tiempo real no está conectado en esta instalación.'**
  String get mapLiveNotConfigured;

  /// No description provided for @mapLiveLoading.
  ///
  /// In es_UY, this message translates to:
  /// **'Consultando ómnibus en vivo…'**
  String get mapLiveLoading;

  /// No description provided for @mapLiveEmpty.
  ///
  /// In es_UY, this message translates to:
  /// **'El STM no reporta ómnibus en vivo cerca de este punto.'**
  String get mapLiveEmpty;

  /// No description provided for @mapLiveServiceDown.
  ///
  /// In es_UY, this message translates to:
  /// **'El servicio de ómnibus en vivo no está disponible.'**
  String get mapLiveServiceDown;

  /// No description provided for @mapBusAge.
  ///
  /// In es_UY, this message translates to:
  /// **'hace {seconds} s'**
  String mapBusAge(int seconds);

  /// No description provided for @mapLiveError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo actualizar el tiempo real: {message}'**
  String mapLiveError(String message);

  /// No description provided for @mapLiveUpdated.
  ///
  /// In es_UY, this message translates to:
  /// **'Recibido a las {time}'**
  String mapLiveUpdated(String time);

  /// No description provided for @mapStopsLoading.
  ///
  /// In es_UY, this message translates to:
  /// **'Cargando paradas y recorridos oficiales…'**
  String get mapStopsLoading;

  /// No description provided for @mapStopsError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudieron consultar las paradas: {message}'**
  String mapStopsError(String message);

  /// No description provided for @mapRoutesLoading.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscando líneas y recorridos…'**
  String get mapRoutesLoading;

  /// No description provided for @mapRoutesError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudieron consultar las líneas: {message}'**
  String mapRoutesError(String message);

  /// No description provided for @mapRouteNoVariants.
  ///
  /// In es_UY, this message translates to:
  /// **'No hay variantes de recorrido para esta línea.'**
  String get mapRouteNoVariants;

  /// No description provided for @mapRouteNoGeometry.
  ///
  /// In es_UY, this message translates to:
  /// **'El feed no incluye la geometría de este recorrido.'**
  String get mapRouteNoGeometry;

  /// No description provided for @mapRouteShowOnMap.
  ///
  /// In es_UY, this message translates to:
  /// **'Ver recorrido en el mapa'**
  String get mapRouteShowOnMap;

  /// No description provided for @mapFeedLoading.
  ///
  /// In es_UY, this message translates to:
  /// **'Descargando y preparando los datos oficiales…'**
  String get mapFeedLoading;

  /// No description provided for @mapFeedDemoOnly.
  ///
  /// In es_UY, this message translates to:
  /// **'La muestra de prueba no contiene recorridos reales.'**
  String get mapFeedDemoOnly;

  /// No description provided for @mapFeedError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudieron cargar los datos oficiales: {message}'**
  String mapFeedError(String message);

  /// No description provided for @mapFeedUnknownError.
  ///
  /// In es_UY, this message translates to:
  /// **'Revisá la conexión e intentá actualizar de nuevo.'**
  String get mapFeedUnknownError;

  /// No description provided for @mapFeedProxyHint.
  ///
  /// In es_UY, this message translates to:
  /// **'En debug, iniciá python tool/montevideo_api_proxy.py en la computadora. En un teléfono por USB, usá adb reverse tcp:8765 tcp:8765 y RUMBO_API_BASE_URL=http://127.0.0.1:8765.'**
  String get mapFeedProxyHint;

  /// No description provided for @locationRecenter.
  ///
  /// In es_UY, this message translates to:
  /// **'Usar mi ubicación'**
  String get locationRecenter;

  /// No description provided for @locationRationaleTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Usar tu ubicación'**
  String get locationRationaleTitle;

  /// No description provided for @locationRationaleBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Rumbo la usa para centrar el mapa. La ubicación se procesa en este dispositivo y no se guarda. El proveedor de mapas puede inferir la zona aproximada por las teselas que se solicitan.'**
  String get locationRationaleBody;

  /// No description provided for @locationRationaleContinue.
  ///
  /// In es_UY, this message translates to:
  /// **'Continuar'**
  String get locationRationaleContinue;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In es_UY, this message translates to:
  /// **'Sin permiso, el mapa sigue disponible desde Montevideo.'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionDeniedForever.
  ///
  /// In es_UY, this message translates to:
  /// **'El permiso está bloqueado en los ajustes del sistema.'**
  String get locationPermissionDeniedForever;

  /// No description provided for @locationServiceDisabled.
  ///
  /// In es_UY, this message translates to:
  /// **'Los servicios de ubicación están desactivados.'**
  String get locationServiceDisabled;

  /// No description provided for @locationError.
  ///
  /// In es_UY, this message translates to:
  /// **'No pudimos obtener tu ubicación. Probá de nuevo.'**
  String get locationError;

  /// No description provided for @locationRetry.
  ///
  /// In es_UY, this message translates to:
  /// **'Reintentar'**
  String get locationRetry;

  /// No description provided for @locationOpenSettings.
  ///
  /// In es_UY, this message translates to:
  /// **'Abrir ajustes'**
  String get locationOpenSettings;

  /// No description provided for @locationEnableService.
  ///
  /// In es_UY, this message translates to:
  /// **'Activar ubicación'**
  String get locationEnableService;

  /// No description provided for @mapLogoSemanticLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Símbolo provisional de Rumbo'**
  String get mapLogoSemanticLabel;

  /// No description provided for @favoritesScreenTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Favoritos'**
  String get favoritesScreenTitle;

  /// No description provided for @favoritesEmptyTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Todavía no guardaste favoritos'**
  String get favoritesEmptyTitle;

  /// No description provided for @favoritesEmptyBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Guardá paradas o líneas desde el mapa y definí Casa y Trabajo para llegar más rápido.'**
  String get favoritesEmptyBody;

  /// No description provided for @favoritesLoading.
  ///
  /// In es_UY, this message translates to:
  /// **'Cargando favoritos…'**
  String get favoritesLoading;

  /// No description provided for @favoritesLoadErrorTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudieron cargar tus favoritos'**
  String get favoritesLoadErrorTitle;

  /// No description provided for @favoritesLoadErrorBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Revisá el almacenamiento del dispositivo e intentá de nuevo.'**
  String get favoritesLoadErrorBody;

  /// No description provided for @favoritesPlacesSection.
  ///
  /// In es_UY, this message translates to:
  /// **'Lugares'**
  String get favoritesPlacesSection;

  /// No description provided for @favoritesStopsSection.
  ///
  /// In es_UY, this message translates to:
  /// **'Paradas'**
  String get favoritesStopsSection;

  /// No description provided for @favoritesLinesSection.
  ///
  /// In es_UY, this message translates to:
  /// **'Líneas'**
  String get favoritesLinesSection;

  /// No description provided for @favoritesHome.
  ///
  /// In es_UY, this message translates to:
  /// **'Casa'**
  String get favoritesHome;

  /// No description provided for @favoritesWork.
  ///
  /// In es_UY, this message translates to:
  /// **'Trabajo'**
  String get favoritesWork;

  /// No description provided for @favoritesPlaceNotSet.
  ///
  /// In es_UY, this message translates to:
  /// **'Todavía sin definir'**
  String get favoritesPlaceNotSet;

  /// No description provided for @favoritesDefine.
  ///
  /// In es_UY, this message translates to:
  /// **'Definir'**
  String get favoritesDefine;

  /// No description provided for @favoritesDefinePlace.
  ///
  /// In es_UY, this message translates to:
  /// **'Definir {name}'**
  String favoritesDefinePlace(String name);

  /// No description provided for @favoritesEmptyStops.
  ///
  /// In es_UY, this message translates to:
  /// **'Todavía no guardaste paradas. Abrí una parada en el mapa y tocá el corazón.'**
  String get favoritesEmptyStops;

  /// No description provided for @favoritesEmptyLines.
  ///
  /// In es_UY, this message translates to:
  /// **'Todavía no guardaste líneas. Expandí una línea en el mapa y tocá el corazón.'**
  String get favoritesEmptyLines;

  /// No description provided for @favoritesHelp.
  ///
  /// In es_UY, this message translates to:
  /// **'Deslizá para eliminar. Mantené presionado para renombrar.'**
  String get favoritesHelp;

  /// No description provided for @favoritesRemoved.
  ///
  /// In es_UY, this message translates to:
  /// **'Se eliminó «{name}»'**
  String favoritesRemoved(String name);

  /// No description provided for @favoritesRenameTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Renombrar favorito'**
  String get favoritesRenameTitle;

  /// No description provided for @favoritesNameLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Nombre'**
  String get favoritesNameLabel;

  /// No description provided for @favoritesStopSubtitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Parada'**
  String get favoritesStopSubtitle;

  /// No description provided for @favoritesLineSubtitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Línea'**
  String get favoritesLineSubtitle;

  /// No description provided for @favoritesPlaceSubtitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Lugar guardado'**
  String get favoritesPlaceSubtitle;

  /// No description provided for @favoritesPlanTo.
  ///
  /// In es_UY, this message translates to:
  /// **'Planificar viaje a {name}'**
  String favoritesPlanTo(String name);

  /// No description provided for @favoritesShowLineOnMap.
  ///
  /// In es_UY, this message translates to:
  /// **'Ver la línea {name} en el mapa'**
  String favoritesShowLineOnMap(String name);

  /// No description provided for @stopFavoriteSave.
  ///
  /// In es_UY, this message translates to:
  /// **'Guardar parada'**
  String get stopFavoriteSave;

  /// No description provided for @stopFavoriteRemove.
  ///
  /// In es_UY, this message translates to:
  /// **'Quitar de favoritos'**
  String get stopFavoriteRemove;

  /// No description provided for @lineFavoriteSave.
  ///
  /// In es_UY, this message translates to:
  /// **'Guardar línea'**
  String get lineFavoriteSave;

  /// No description provided for @lineFavoriteRemove.
  ///
  /// In es_UY, this message translates to:
  /// **'Quitar línea de favoritos'**
  String get lineFavoriteRemove;

  /// No description provided for @actionSave.
  ///
  /// In es_UY, this message translates to:
  /// **'Guardar'**
  String get actionSave;

  /// No description provided for @actionUndo.
  ///
  /// In es_UY, this message translates to:
  /// **'Deshacer'**
  String get actionUndo;

  /// No description provided for @settingsScreenTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Ajustes'**
  String get settingsScreenTitle;

  /// No description provided for @settingsIntro.
  ///
  /// In es_UY, this message translates to:
  /// **'Personalizá Rumbo a tu gusto.'**
  String get settingsIntro;

  /// No description provided for @themePreferenceTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Apariencia'**
  String get themePreferenceTitle;

  /// No description provided for @themePreferenceDescription.
  ///
  /// In es_UY, this message translates to:
  /// **'Elegí cómo se ve la app.'**
  String get themePreferenceDescription;

  /// No description provided for @themeLight.
  ///
  /// In es_UY, this message translates to:
  /// **'Claro'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In es_UY, this message translates to:
  /// **'Oscuro'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In es_UY, this message translates to:
  /// **'Sistema'**
  String get themeSystem;

  /// No description provided for @settingsLoadError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo cargar la preferencia de apariencia.'**
  String get settingsLoadError;

  /// No description provided for @remotePlaceSearchTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscar direcciones en línea'**
  String get remotePlaceSearchTitle;

  /// No description provided for @remotePlaceSearchDescription.
  ///
  /// In es_UY, this message translates to:
  /// **'Al buscar, el texto escrito se envía al servicio remoto. Mientras escribís, solo se buscan datos locales.'**
  String get remotePlaceSearchDescription;

  /// No description provided for @debugThemeSample.
  ///
  /// In es_UY, this message translates to:
  /// **'Muestra de identidad visual'**
  String get debugThemeSample;

  /// No description provided for @debugThemeSampleTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Identidad visual'**
  String get debugThemeSampleTitle;

  /// No description provided for @debugPaletteTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Paleta Rumbo'**
  String get debugPaletteTitle;

  /// No description provided for @debugTypographyTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Tipografía Inter'**
  String get debugTypographyTitle;

  /// No description provided for @debugTypographyBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Texto de cuerpo con escala del sistema.'**
  String get debugTypographyBody;

  /// No description provided for @debugAccentLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Acento: destino'**
  String get debugAccentLabel;

  /// No description provided for @debugErrorLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Error'**
  String get debugErrorLabel;

  /// No description provided for @debugLineChipsTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Líneas de ejemplo'**
  String get debugLineChipsTitle;

  /// No description provided for @debugBodyText.
  ///
  /// In es_UY, this message translates to:
  /// **'Tu ciudad. Tu camino.'**
  String get debugBodyText;

  /// No description provided for @debugPaletteInk.
  ///
  /// In es_UY, this message translates to:
  /// **'Ink'**
  String get debugPaletteInk;

  /// No description provided for @debugPaletteIvory.
  ///
  /// In es_UY, this message translates to:
  /// **'Ivory'**
  String get debugPaletteIvory;

  /// No description provided for @debugPaletteDeepBlue.
  ///
  /// In es_UY, this message translates to:
  /// **'Deep blue'**
  String get debugPaletteDeepBlue;

  /// No description provided for @debugPaletteMint.
  ///
  /// In es_UY, this message translates to:
  /// **'Mint AA'**
  String get debugPaletteMint;

  /// No description provided for @debugPaletteLime.
  ///
  /// In es_UY, this message translates to:
  /// **'Lima de identidad'**
  String get debugPaletteLime;

  /// No description provided for @debugPaletteSurface.
  ///
  /// In es_UY, this message translates to:
  /// **'Superficie'**
  String get debugPaletteSurface;

  /// No description provided for @debugPaletteDarkSurface.
  ///
  /// In es_UY, this message translates to:
  /// **'Superficie oscura'**
  String get debugPaletteDarkSurface;

  /// No description provided for @debugPaletteDarkElevated.
  ///
  /// In es_UY, this message translates to:
  /// **'Superficie elevada'**
  String get debugPaletteDarkElevated;

  /// No description provided for @transitDataTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Datos de transporte'**
  String get transitDataTitle;

  /// No description provided for @transitDataLoading.
  ///
  /// In es_UY, this message translates to:
  /// **'Cargando datos de prueba…'**
  String get transitDataLoading;

  /// No description provided for @transitSourceLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Fuente'**
  String get transitSourceLabel;

  /// No description provided for @transitVersionLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Versión'**
  String get transitVersionLabel;

  /// No description provided for @transitUpdatedLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Última actualización'**
  String get transitUpdatedLabel;

  /// No description provided for @transitValidityLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Vigencia'**
  String get transitValidityLabel;

  /// No description provided for @transitCurrent.
  ///
  /// In es_UY, this message translates to:
  /// **'Vigente'**
  String get transitCurrent;

  /// No description provided for @transitExpired.
  ///
  /// In es_UY, this message translates to:
  /// **'Desactualizado'**
  String get transitExpired;

  /// No description provided for @transitCounts.
  ///
  /// In es_UY, this message translates to:
  /// **'{stops} paradas · {routes} líneas'**
  String transitCounts(int stops, int routes);

  /// No description provided for @transitUpdateNow.
  ///
  /// In es_UY, this message translates to:
  /// **'Actualizar ahora'**
  String get transitUpdateNow;

  /// No description provided for @transitDemoNotice.
  ///
  /// In es_UY, this message translates to:
  /// **'Datos sintéticos para probar la app; no son datos reales del STM.'**
  String get transitDemoNotice;

  /// No description provided for @transitNoSource.
  ///
  /// In es_UY, this message translates to:
  /// **'La URL oficial del feed no está configurada.'**
  String get transitNoSource;

  /// No description provided for @transitAttributionLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Atribución'**
  String get transitAttributionLabel;

  /// No description provided for @transitLicenseLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Licencia'**
  String get transitLicenseLabel;

  /// No description provided for @transitNoData.
  ///
  /// In es_UY, this message translates to:
  /// **'No hay datos disponibles.'**
  String get transitNoData;

  /// No description provided for @transitUpdatedAtNone.
  ///
  /// In es_UY, this message translates to:
  /// **'Todavía no actualizado'**
  String get transitUpdatedAtNone;

  /// No description provided for @transitUpdateError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo actualizar; se conservan los datos guardados.'**
  String get transitUpdateError;

  /// No description provided for @transitUnknownValue.
  ///
  /// In es_UY, this message translates to:
  /// **'—'**
  String get transitUnknownValue;

  /// No description provided for @tripSearchTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Planificá tu viaje'**
  String get tripSearchTitle;

  /// No description provided for @tripOriginLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Desde'**
  String get tripOriginLabel;

  /// No description provided for @tripDestinationLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Hasta'**
  String get tripDestinationLabel;

  /// No description provided for @tripOriginLocationHint.
  ///
  /// In es_UY, this message translates to:
  /// **'Mi ubicación'**
  String get tripOriginLocationHint;

  /// No description provided for @tripOriginStopHint.
  ///
  /// In es_UY, this message translates to:
  /// **'Elegí una parada de origen'**
  String get tripOriginStopHint;

  /// No description provided for @tripDestinationHint.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscá una parada'**
  String get tripDestinationHint;

  /// No description provided for @tripUseCurrentLocation.
  ///
  /// In es_UY, this message translates to:
  /// **'Usar mi ubicación'**
  String get tripUseCurrentLocation;

  /// No description provided for @tripTimingLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Horario del viaje'**
  String get tripTimingLabel;

  /// No description provided for @tripTimingNow.
  ///
  /// In es_UY, this message translates to:
  /// **'Salir ahora'**
  String get tripTimingNow;

  /// No description provided for @tripTimingDepartAt.
  ///
  /// In es_UY, this message translates to:
  /// **'Salir a las…'**
  String get tripTimingDepartAt;

  /// No description provided for @tripTimingArriveBy.
  ///
  /// In es_UY, this message translates to:
  /// **'Llegar a las…'**
  String get tripTimingArriveBy;

  /// No description provided for @tripTimingSummaryNow.
  ///
  /// In es_UY, this message translates to:
  /// **'Salida: ahora'**
  String get tripTimingSummaryNow;

  /// No description provided for @tripTimingSummaryDepart.
  ///
  /// In es_UY, this message translates to:
  /// **'Salida: {day} · {time}'**
  String tripTimingSummaryDepart(String day, String time);

  /// No description provided for @tripTimingSummaryArrive.
  ///
  /// In es_UY, this message translates to:
  /// **'Llegada: {day} · {time}'**
  String tripTimingSummaryArrive(String day, String time);

  /// No description provided for @tripDayToday.
  ///
  /// In es_UY, this message translates to:
  /// **'Hoy'**
  String get tripDayToday;

  /// No description provided for @tripDayTomorrow.
  ///
  /// In es_UY, this message translates to:
  /// **'Mañana'**
  String get tripDayTomorrow;

  /// No description provided for @tripPastTime.
  ///
  /// In es_UY, this message translates to:
  /// **'Esa hora ya pasó. Elegí una hora futura.'**
  String get tripPastTime;

  /// No description provided for @tripNoArrivalTrips.
  ///
  /// In es_UY, this message translates to:
  /// **'No hay viajes que lleguen a esa hora'**
  String get tripNoArrivalTrips;

  /// No description provided for @tripDepartureLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Salida'**
  String get tripDepartureLabel;

  /// No description provided for @tripChangeDate.
  ///
  /// In es_UY, this message translates to:
  /// **'Cambiar fecha'**
  String get tripChangeDate;

  /// No description provided for @tripChangeTime.
  ///
  /// In es_UY, this message translates to:
  /// **'Cambiar hora'**
  String get tripChangeTime;

  /// No description provided for @tripNoStops.
  ///
  /// In es_UY, this message translates to:
  /// **'No encontramos paradas con ese nombre.'**
  String get tripNoStops;

  /// No description provided for @tripNoPlaces.
  ///
  /// In es_UY, this message translates to:
  /// **'No encontramos lugares o direcciones con ese texto.'**
  String get tripNoPlaces;

  /// No description provided for @tripSearchError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo buscar: {error}'**
  String tripSearchError(String error);

  /// No description provided for @tripShowTrips.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscar ómnibus'**
  String get tripShowTrips;

  /// No description provided for @tripSearchingTrips.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscando opciones…'**
  String get tripSearchingTrips;

  /// No description provided for @tripLocationUnavailable.
  ///
  /// In es_UY, this message translates to:
  /// **'Elegí una parada de origen o activá tu ubicación desde el mapa.'**
  String get tripLocationUnavailable;

  /// No description provided for @tripNoTrips.
  ///
  /// In es_UY, this message translates to:
  /// **'No encontramos viajes con los horarios disponibles.'**
  String get tripNoTrips;

  /// No description provided for @tripStaticScheduleNotice.
  ///
  /// In es_UY, this message translates to:
  /// **'Opciones basadas en horarios programados; no son arribos en vivo.'**
  String get tripStaticScheduleNotice;

  /// No description provided for @tripOfficialDataUnavailable.
  ///
  /// In es_UY, this message translates to:
  /// **'El GTFS oficial todavía no está disponible. Iniciá el proxy local y reintentá la actualización.'**
  String get tripOfficialDataUnavailable;

  /// No description provided for @tripOriginRequired.
  ///
  /// In es_UY, this message translates to:
  /// **'Elegí una parada de origen o activá tu ubicación desde el mapa.'**
  String get tripOriginRequired;

  /// No description provided for @tripSearchPlaces.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscar lugares o direcciones'**
  String get tripSearchPlaces;

  /// No description provided for @tripPlaceResult.
  ///
  /// In es_UY, this message translates to:
  /// **'Lugar o dirección · OpenStreetMap'**
  String get tripPlaceResult;

  /// No description provided for @tripStopResult.
  ///
  /// In es_UY, this message translates to:
  /// **'Parada del STM'**
  String get tripStopResult;

  /// No description provided for @tripGeocodingPrivacy.
  ///
  /// In es_UY, this message translates to:
  /// **'Al tocar «Buscar lugares o direcciones», se envía el texto escrito al servicio remoto. La ubicación actual no se envía.'**
  String get tripGeocodingPrivacy;

  /// No description provided for @tripPlaceSearchUnavailable.
  ///
  /// In es_UY, this message translates to:
  /// **'La búsqueda de lugares no está configurada en esta instalación.'**
  String get tripPlaceSearchUnavailable;

  /// No description provided for @tripPlanError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo planificar: {error}'**
  String tripPlanError(String error);

  /// No description provided for @tripSortLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Ordenar por'**
  String get tripSortLabel;

  /// No description provided for @tripSortFastest.
  ///
  /// In es_UY, this message translates to:
  /// **'Más rápido'**
  String get tripSortFastest;

  /// No description provided for @tripSortLeastWalking.
  ///
  /// In es_UY, this message translates to:
  /// **'Menos caminata'**
  String get tripSortLeastWalking;

  /// No description provided for @tripSortFewestTransfers.
  ///
  /// In es_UY, this message translates to:
  /// **'Menos transbordos'**
  String get tripSortFewestTransfers;

  /// No description provided for @tripWalkingLimitLabel.
  ///
  /// In es_UY, this message translates to:
  /// **'Caminata máxima'**
  String get tripWalkingLimitLabel;

  /// No description provided for @tripWalkingMeters.
  ///
  /// In es_UY, this message translates to:
  /// **'{meters} m'**
  String tripWalkingMeters(int meters);

  /// No description provided for @tripWalkOnly.
  ///
  /// In es_UY, this message translates to:
  /// **'Caminar {meters} m'**
  String tripWalkOnly(int meters);

  /// No description provided for @tripPlanTimes.
  ///
  /// In es_UY, this message translates to:
  /// **'{departure}–{arrival}'**
  String tripPlanTimes(String departure, String arrival);

  /// No description provided for @tripPlanDuration.
  ///
  /// In es_UY, this message translates to:
  /// **'{minutes} min'**
  String tripPlanDuration(int minutes);

  /// No description provided for @tripPlanWalkingMinutes.
  ///
  /// In es_UY, this message translates to:
  /// **'{minutes} min de caminata'**
  String tripPlanWalkingMinutes(int minutes);

  /// No description provided for @tripPlanTransfers.
  ///
  /// In es_UY, this message translates to:
  /// **'{count, plural, =0{Sin transbordos} one{1 transbordo} other{{count} transbordos}}'**
  String tripPlanTransfers(int count);

  /// No description provided for @tripPlanNoLines.
  ///
  /// In es_UY, this message translates to:
  /// **'ninguna'**
  String get tripPlanNoLines;

  /// No description provided for @tripPlanSemantics.
  ///
  /// In es_UY, this message translates to:
  /// **'Salida {departure}, llegada {arrival}. {minutes} min de viaje, {walking} min de caminata, {transfers, plural, =0{sin transbordos} one{1 transbordo} other{{transfers} transbordos}}. Líneas: {lines}. Horarios programados.'**
  String tripPlanSemantics(
    String departure,
    String arrival,
    int minutes,
    int walking,
    int transfers,
    String lines,
  );

  /// No description provided for @tripScheduledTimes.
  ///
  /// In es_UY, this message translates to:
  /// **'Horarios programados'**
  String get tripScheduledTimes;

  /// No description provided for @tripEmptySuggestions.
  ///
  /// In es_UY, this message translates to:
  /// **'Probá ampliar la caminata máxima o cambiar la hora.'**
  String get tripEmptySuggestions;

  /// No description provided for @tripEmptyExpandWalking.
  ///
  /// In es_UY, this message translates to:
  /// **'Ampliar caminata'**
  String get tripEmptyExpandWalking;

  /// No description provided for @tripEmptyChangeTime.
  ///
  /// In es_UY, this message translates to:
  /// **'Cambiar hora'**
  String get tripEmptyChangeTime;

  /// No description provided for @activeTripStart.
  ///
  /// In es_UY, this message translates to:
  /// **'Iniciar viaje con avisos'**
  String get activeTripStart;

  /// No description provided for @activeTripFinish.
  ///
  /// In es_UY, this message translates to:
  /// **'Finalizar viaje'**
  String get activeTripFinish;

  /// No description provided for @activeTripNoTransit.
  ///
  /// In es_UY, this message translates to:
  /// **'Este plan no tiene tramos en ómnibus para activar avisos.'**
  String get activeTripNoTransit;

  /// No description provided for @activeTripRouteUnavailable.
  ///
  /// In es_UY, this message translates to:
  /// **'No están disponibles las paradas de esta variante.'**
  String get activeTripRouteUnavailable;

  /// No description provided for @activeTripUnsupported.
  ///
  /// In es_UY, this message translates to:
  /// **'El viaje activo solo está disponible en Android y iOS.'**
  String get activeTripUnsupported;

  /// No description provided for @activeTripLocationDisabled.
  ///
  /// In es_UY, this message translates to:
  /// **'Activá la ubicación para iniciar el seguimiento.'**
  String get activeTripLocationDisabled;

  /// No description provided for @activeTripNotificationsRequired.
  ///
  /// In es_UY, this message translates to:
  /// **'Habilitá las notificaciones de Rumbo para recibir avisos de bajada.'**
  String get activeTripNotificationsRequired;

  /// No description provided for @activeTripPermissionTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Permiso de ubicación en segundo plano'**
  String get activeTripPermissionTitle;

  /// No description provided for @activeTripPermissionBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Para avisarte cuándo acercarte a bajar aunque uses otras aplicaciones, habilitá «Permitir siempre» en los ajustes. La ubicación se procesa en este dispositivo y el seguimiento se detiene al finalizar el viaje.'**
  String get activeTripPermissionBody;

  /// No description provided for @activeTripOpenSettings.
  ///
  /// In es_UY, this message translates to:
  /// **'Abrir ajustes'**
  String get activeTripOpenSettings;

  /// No description provided for @activeTripStarted.
  ///
  /// In es_UY, this message translates to:
  /// **'Seguimiento activo. Podés usar otras aplicaciones; Rumbo te avisará cuándo bajar.'**
  String get activeTripStarted;

  /// No description provided for @activeTripNotificationTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Rumbo · viaje activo'**
  String get activeTripNotificationTitle;

  /// No description provided for @activeTripNotificationProgress.
  ///
  /// In es_UY, this message translates to:
  /// **'Quedan {stops} paradas hasta {stop}'**
  String activeTripNotificationProgress(String stops, String stop);

  /// No description provided for @activeTripStopsRemaining.
  ///
  /// In es_UY, this message translates to:
  /// **'Quedan {stops} paradas hasta {stop}'**
  String activeTripStopsRemaining(int stops, String stop);

  /// No description provided for @activeTripAlertTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Próxima parada'**
  String get activeTripAlertTitle;

  /// No description provided for @activeTripAlertBody.
  ///
  /// In es_UY, this message translates to:
  /// **'Acercate a bajar en {stop}.'**
  String activeTripAlertBody(String stop);

  /// No description provided for @activeTripBackgroundNotice.
  ///
  /// In es_UY, this message translates to:
  /// **'Rumbo está siguiendo tu viaje en este dispositivo.'**
  String get activeTripBackgroundNotice;

  /// No description provided for @tripDetailTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Tu recorrido'**
  String get tripDetailTitle;

  /// No description provided for @tripDetailBetweenStops.
  ///
  /// In es_UY, this message translates to:
  /// **'{from} → {to}'**
  String tripDetailBetweenStops(String from, String to);

  /// No description provided for @tripDetailWalkingTotal.
  ///
  /// In es_UY, this message translates to:
  /// **'Caminata total: {meters} m'**
  String tripDetailWalkingTotal(int meters);

  /// No description provided for @tripDetailUnknownStop.
  ///
  /// In es_UY, this message translates to:
  /// **'Parada'**
  String get tripDetailUnknownStop;

  /// No description provided for @tripDetailStart.
  ///
  /// In es_UY, this message translates to:
  /// **'Salida'**
  String get tripDetailStart;

  /// No description provided for @tripDetailEnd.
  ///
  /// In es_UY, this message translates to:
  /// **'Llegada'**
  String get tripDetailEnd;

  /// No description provided for @tripDetailWalkStep.
  ///
  /// In es_UY, this message translates to:
  /// **'Caminar {meters} m'**
  String tripDetailWalkStep(int meters);

  /// No description provided for @tripDetailBoard.
  ///
  /// In es_UY, this message translates to:
  /// **'Tomar línea {line} en {stop}'**
  String tripDetailBoard(String line, String stop);

  /// No description provided for @tripDetailAlight.
  ///
  /// In es_UY, this message translates to:
  /// **'Bajar en {stop}'**
  String tripDetailAlight(String stop);

  /// No description provided for @tripDetailToward.
  ///
  /// In es_UY, this message translates to:
  /// **'Hacia {direction}'**
  String tripDetailToward(String direction);

  /// No description provided for @tripDetailEstimatedTime.
  ///
  /// In es_UY, this message translates to:
  /// **'{time} · estimado'**
  String tripDetailEstimatedTime(String time);

  /// No description provided for @tripDetailWalkingApproximate.
  ///
  /// In es_UY, this message translates to:
  /// **'Caminata aproximada, en línea recta.'**
  String get tripDetailWalkingApproximate;

  /// No description provided for @tripDetailScheduleNotice.
  ///
  /// In es_UY, this message translates to:
  /// **'Horarios programados, sin ETA en vivo. El trazo del ómnibus une paradas de forma esquemática y no es navegación guiada.'**
  String get tripDetailScheduleNotice;

  /// No description provided for @tripDetailChangeTrip.
  ///
  /// In es_UY, this message translates to:
  /// **'Cambiar viaje'**
  String get tripDetailChangeTrip;

  /// No description provided for @tripDetailClose.
  ///
  /// In es_UY, this message translates to:
  /// **'Cerrar recorrido'**
  String get tripDetailClose;

  /// No description provided for @searchHint.
  ///
  /// In es_UY, this message translates to:
  /// **'Buscá una calle, esquina, parada o lugar…'**
  String get searchHint;

  /// No description provided for @searchRecent.
  ///
  /// In es_UY, this message translates to:
  /// **'Búsquedas recientes'**
  String get searchRecent;

  /// No description provided for @searchClearRecent.
  ///
  /// In es_UY, this message translates to:
  /// **'Borrar historial'**
  String get searchClearRecent;

  /// No description provided for @searchEmptyTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Sin resultados'**
  String get searchEmptyTitle;

  /// No description provided for @searchEmptyBody.
  ///
  /// In es_UY, this message translates to:
  /// **'No encontramos coincidencias para «{query}».'**
  String searchEmptyBody(String query);

  /// No description provided for @searchOfflineNotice.
  ///
  /// In es_UY, this message translates to:
  /// **'Sin conexión a internet. Mostrando solo paradas y datos locales.'**
  String get searchOfflineNotice;

  /// No description provided for @searchKindStop.
  ///
  /// In es_UY, this message translates to:
  /// **'Parada de ómnibus'**
  String get searchKindStop;

  /// No description provided for @searchKindAddress.
  ///
  /// In es_UY, this message translates to:
  /// **'Dirección'**
  String get searchKindAddress;

  /// No description provided for @searchKindIntersection.
  ///
  /// In es_UY, this message translates to:
  /// **'Esquina'**
  String get searchKindIntersection;

  /// No description provided for @searchKindPoi.
  ///
  /// In es_UY, this message translates to:
  /// **'Lugar de interés'**
  String get searchKindPoi;

  /// No description provided for @searchKindNeighborhood.
  ///
  /// In es_UY, this message translates to:
  /// **'Barrio'**
  String get searchKindNeighborhood;

  /// No description provided for @searchKindRoute.
  ///
  /// In es_UY, this message translates to:
  /// **'Línea STM'**
  String get searchKindRoute;

  /// No description provided for @searchKindRecent.
  ///
  /// In es_UY, this message translates to:
  /// **'Reciente'**
  String get searchKindRecent;

  /// No description provided for @searchKindFavorite.
  ///
  /// In es_UY, this message translates to:
  /// **'Favorito'**
  String get searchKindFavorite;

  /// No description provided for @lineDetailTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Línea {name}'**
  String lineDetailTitle(String name);

  /// No description provided for @lineDetailVariant.
  ///
  /// In es_UY, this message translates to:
  /// **'Variante'**
  String get lineDetailVariant;

  /// No description provided for @lineDetailDirection.
  ///
  /// In es_UY, this message translates to:
  /// **'Hacia {destination}'**
  String lineDetailDirection(String destination);

  /// No description provided for @lineDetailStopsTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Paradas del recorrido'**
  String get lineDetailStopsTitle;

  /// No description provided for @lineDetailStopCount.
  ///
  /// In es_UY, this message translates to:
  /// **'{count, plural, =1{1 parada} other{{count} paradas}}'**
  String lineDetailStopCount(int count);

  /// No description provided for @lineDetailUpcomingDepartures.
  ///
  /// In es_UY, this message translates to:
  /// **'Próximas salidas estimadas'**
  String get lineDetailUpcomingDepartures;

  /// No description provided for @lineDetailNoDepartures.
  ///
  /// In es_UY, this message translates to:
  /// **'No hay más salidas estimadas para hoy.'**
  String get lineDetailNoDepartures;

  /// No description provided for @lineDetailDepartureEstimated.
  ///
  /// In es_UY, this message translates to:
  /// **'{time} · estimado'**
  String lineDetailDepartureEstimated(String time);

  /// No description provided for @lineDetailLiveBuses.
  ///
  /// In es_UY, this message translates to:
  /// **'Ómnibus en vivo'**
  String get lineDetailLiveBuses;

  /// No description provided for @lineDetailLiveBusesCount.
  ///
  /// In es_UY, this message translates to:
  /// **'{count, plural, =0{Sin ómnibus en vivo en este momento} one{1 ómnibus en circulación} other{{count} ómnibus en circulación}}'**
  String lineDetailLiveBusesCount(int count);

  /// No description provided for @lineDetailEmpty.
  ///
  /// In es_UY, this message translates to:
  /// **'No hay información disponible para esta línea.'**
  String get lineDetailEmpty;

  /// No description provided for @lineDetailNoVariants.
  ///
  /// In es_UY, this message translates to:
  /// **'No se encontraron recorridos para esta línea.'**
  String get lineDetailNoVariants;

  /// No description provided for @lineDetailError.
  ///
  /// In es_UY, this message translates to:
  /// **'No se pudo cargar el detalle de la línea: {message}'**
  String lineDetailError(String message);

  /// No description provided for @lineDetailOffline.
  ///
  /// In es_UY, this message translates to:
  /// **'Sin conexión. Los horarios y paradas mostrados son los guardados.'**
  String get lineDetailOffline;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'es':
      {
        switch (locale.countryCode) {
          case 'UY':
            return AppLocalizationsEsUy();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
