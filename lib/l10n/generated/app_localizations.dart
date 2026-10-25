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
  /// **'Cuando guardes una parada o un lugar, lo vas a encontrar acá.'**
  String get favoritesEmptyBody;

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

  /// No description provided for @tripPlanSummary.
  ///
  /// In es_UY, this message translates to:
  /// **'{minutes} min · {transfers, plural, =0{sin transbordos} one{1 transbordo} other{{transfers} transbordos}} · llega {arrival}'**
  String tripPlanSummary(int minutes, int transfers, String arrival);

  /// No description provided for @tripDetailTitle.
  ///
  /// In es_UY, this message translates to:
  /// **'Tu recorrido'**
  String get tripDetailTitle;

  /// No description provided for @tripDetailDeparture.
  ///
  /// In es_UY, this message translates to:
  /// **'Salida · {origin} · {time}'**
  String tripDetailDeparture(String origin, String time);

  /// No description provided for @tripDetailArrival.
  ///
  /// In es_UY, this message translates to:
  /// **'Llegada · {destination} · {time}'**
  String tripDetailArrival(String destination, String time);

  /// No description provided for @tripDetailWalking.
  ///
  /// In es_UY, this message translates to:
  /// **'Caminá {meters} m · {minutes} min'**
  String tripDetailWalking(int meters, int minutes);

  /// No description provided for @tripDetailWait.
  ///
  /// In es_UY, this message translates to:
  /// **'Esperá en {stop} · {minutes} min'**
  String tripDetailWait(String stop, int minutes);

  /// No description provided for @tripDetailTransfer.
  ///
  /// In es_UY, this message translates to:
  /// **'Transbordo en {stop} · {minutes} min'**
  String tripDetailTransfer(String stop, int minutes);

  /// No description provided for @tripDetailBus.
  ///
  /// In es_UY, this message translates to:
  /// **'Ómnibus {line}'**
  String tripDetailBus(String line);

  /// No description provided for @tripDetailBusDirection.
  ///
  /// In es_UY, this message translates to:
  /// **'Ómnibus {line} hacia {direction}'**
  String tripDetailBusDirection(String line, String direction);

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

  /// No description provided for @tripDetailScheduleNotice.
  ///
  /// In es_UY, this message translates to:
  /// **'Horarios programados, no ETA en vivo. La caminata es aproximada y el trazo del ómnibus une paradas de forma esquemática; no es navegación guiada.'**
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
