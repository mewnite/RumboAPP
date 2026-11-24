const STM_API = 'https://api.montevideo.gub.uy/api/transportepublico';
const STM_TOKEN = 'https://mvdapi-auth.montevideo.gub.uy/auth/realms/pci/protocol/openid-connect/token';
const GEOCODING_API = 'https://nominatim.openstreetmap.org/search';
const MONTEVIDEO_GEOCODING_VIEWBOX = '-56.4048,-34.7167,-55.9955,-34.9271';
const CACHE_SECONDS = 10;
const STM_TIMEOUT_MS = 15_000;

let tokenCache = {
  value: '',
  expiresAt: 0,
};

function corsHeaders(contentType = 'application/json') {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Accept, Content-Type',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Cache-Control': 'no-store',
    'Content-Type': contentType,
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(),
  });
}

function errorResponse(status, message) {
  return jsonResponse({ error: message }, status);
}

function geocodingQuery(text) {
  const abbreviations = {
    av: 'avenida',
    avda: 'avenida',
    bvar: 'bulevar',
    bvr: 'bulevar',
    bv: 'bulevar',
    gral: 'general',
    cno: 'camino',
    tte: 'teniente',
    dr: 'doctor',
    sta: 'santa',
    sto: 'santo',
    pta: 'punta',
    pto: 'puerto',
    pje: 'pasaje',
    pza: 'plaza',
    rbla: 'rambla',
  };
  const normalized = text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\bn\s*\.?\s*(?:[º°]|ro?\.?|o\.?)\s*(?=\d)/gi, '')
    .replace(
      /\b(avda|av|bvar|bvr|bv|gral|cno|tte|dr|sta|sto|pta|pto|pje|pza|rbla)\b\.?/gi,
      (match) => abbreviations[match.toLowerCase().replace(/\.$/, '')],
    )
    .replace(/\bnuevocentro\b/gi, 'Nuevo Centro')
    .replace(/\s+/g, ' ')
    .trim();
  const intersection = normalized.match(
    /^\s*(.+)\s+(?:y|x|esq\.?(?:\s+(?:de|con))?|esquina(?:\s+(?:de|con))?|con|\/|&)\s+(.+?)\s*$/i,
  );
  const scoped = intersection
    ? `${intersection[1].trim()} & ${intersection[2].trim()}`
    : normalized;
  return /\b(?:montevideo|uruguay)\b/i.test(scoped)
    ? scoped
    : `${scoped}, Montevideo, Uruguay`;
}

function copyResponse(response, cacheSeconds = 0) {
  const headers = new Headers(corsHeaders(
    response.headers.get('content-type') || 'application/json',
  ));
  if (cacheSeconds > 0) {
    headers.set('Cache-Control', `public, max-age=${cacheSeconds}`);
  }
  return new Response(response.body, {
    status: response.status,
    headers,
  });
}

function busesAsGeoJson(payload) {
  if (payload?.type === 'FeatureCollection' && Array.isArray(payload.features)) {
    return payload;
  }
  if (!Array.isArray(payload)) {
    throw new Error('STM no devolvió una lista de buses válida.');
  }
  return {
    type: 'FeatureCollection',
    features: payload.flatMap((bus) => {
      const coordinates = bus?.location?.coordinates;
      if (!Array.isArray(coordinates) || coordinates.length < 2) return [];
      const [
        longitude,
        latitude,
      ] = coordinates;
      if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return [];
      return [{
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [longitude, latitude],
        },
        properties: {
          id: bus.busId,
          codigoEmpresa: 0,
          codigoBus: bus.busId,
          variante: bus.lineVariantId,
          destino: bus.destination || '',
          tipoLinea: 0,
          subsistema: 0,
          velocidad: bus.speed ?? 0,
          linea: bus.line || '',
          sublinea: bus.subline || '',
          destinoDesc: bus.destination || '',
          tipoLineaDesc: 'Ómnibus',
          subsistemaDesc: bus.company || 'STM',
          timestamp: bus.timestamp,
          company: bus.company,
          origin: bus.origin,
          access: bus.access,
          thermalConfort: bus.thermalConfort,
          emissions: bus.emissions,
        },
      }];
    }),
  };
}

async function accessToken(env) {
  const now = Date.now();
  if (tokenCache.value && tokenCache.expiresAt > now + 20_000) {
    return tokenCache.value;
  }
  if (!env.CLIENT_ID || !env.CLIENT_SECRET) {
    throw new Error('Faltan los secretos CLIENT_ID y CLIENT_SECRET.');
  }

  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: env.CLIENT_ID,
    client_secret: env.CLIENT_SECRET,
  });
  const response = await fetch(STM_TOKEN, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!response.ok) {
    throw new Error(`OAuth STM respondió HTTP ${response.status}.`);
  }
  const payload = await response.json();
  if (typeof payload.access_token !== 'string') {
    throw new Error('OAuth STM no devolvió access_token.');
  }
  const lifetime = Number.isFinite(payload.expires_in)
    ? payload.expires_in
    : 60;
  tokenCache = {
    value: payload.access_token,
    expiresAt: now + Math.max(5, lifetime - 20) * 1000,
  };
  return tokenCache.value;
}

async function stmFetch(path, env, accept = 'application/json') {
  const token = await accessToken(env);
  try {
    return await fetch(`${STM_API}${path}`, {
      headers: {
        Accept: accept,
        Authorization: `Bearer ${token}`,
        'User-Agent': 'RumboAPP/1.0',
      },
      signal: AbortSignal.timeout(STM_TIMEOUT_MS),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'TimeoutError') {
      throw new Error('El servicio STM tardó más de 15 segundos en responder.');
    }
    throw new Error('No se pudo conectar con el servicio STM.');
  }
}

function safeBusQuery(url) {
  const output = new URLSearchParams();
  const format = url.searchParams.get('format') || 'geojson';
  const lines = url.searchParams.get('lines');
  if (format !== 'geojson') {
    throw new Error('Solo se permite format=geojson.');
  }
  if (lines && !/^[A-Za-z0-9,-]{1,80}$/.test(lines)) {
    throw new Error('Filtro de líneas inválido.');
  }
  output.set('format', format);
  if (lines) output.set('lines', lines);
  return output.toString();
}

function safeUpcomingQuery(url) {
  const lines = url.searchParams.get('lines');
  const amount = url.searchParams.get('amountperline') || '1';
  if (!lines || !/^[A-Za-z0-9,-]{1,80}$/.test(lines)) {
    throw new Error('Se requiere un filtro de líneas válido.');
  }
  if (!/^[1-5]$/.test(amount)) {
    throw new Error('amountperline debe estar entre 1 y 5.');
  }
  return new URLSearchParams({ lines, amountperline: amount }).toString();
}

async function handle(request, env, ctx) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }
  if (request.method !== 'GET') {
    return errorResponse(405, 'Método no permitido.');
  }

  const url = new URL(request.url);
  if (url.pathname === '/health') {
    return jsonResponse({ status: 'ok' });
  }

  let upstreamPath;
  let cacheSeconds = 0;
  try {
    if (url.pathname === '/api/buses') {
      upstreamPath = `/buses?${safeBusQuery(url)}`;
      cacheSeconds = CACHE_SECONDS;
    } else if (url.pathname === '/gtfs/latest') {
      const cacheKey = new Request(`${url.origin}/gtfs/latest`);
      const cached = await caches.default.match(cacheKey);
      if (cached) return cached;
      const response = await stmFetch(
        '/buses/gtfs/static/latest/google_transit.zip',
        env,
        'application/zip',
      );
      if (!response.ok) {
        return errorResponse(502, `STM respondió HTTP ${response.status}.`);
      }
      const result = copyResponse(response, 86_400);
      ctx.waitUntil(caches.default.put(cacheKey, result.clone()));
      return result;
    } else if (url.pathname === '/geocode') {
      const query = new URLSearchParams();
      const text = url.searchParams.get('q')?.trim() || '';
      if (text.length < 3 || text.length > 160) {
        return errorResponse(400, 'La búsqueda debe tener entre 3 y 160 caracteres.');
      }
      const normalizedText = text
        .toLocaleLowerCase('es')
        .normalize('NFD')
        .replace(/\p{Diacritic}/gu, '')
        .replace(/\s+/g, ' ')
        .trim();
      const cacheKey = new Request(
        `${url.origin}/geocode?q=${encodeURIComponent(normalizedText)}`
      );
      const cache = caches.default;
      const cached = await cache.match(cacheKey);
      if (cached) return cached;
      query.set('q', geocodingQuery(text));
      query.set('format', 'jsonv2');
      query.set('countrycodes', 'uy');
      query.set('addressdetails', '1');
      query.set('limit', '5');
      query.set('viewbox', MONTEVIDEO_GEOCODING_VIEWBOX);
      query.set('bounded', '1');
      const response = await fetch(`${GEOCODING_API}?${query}`, {
        headers: {
          Accept: 'application/json',
          'User-Agent': 'RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)',
        },
      });
      const result = copyResponse(response, 86_400);
      if (response.ok) ctx.waitUntil(cache.put(cacheKey, result.clone()));
      return result;
    } else if (url.pathname === '/api/linevariants') {
      upstreamPath = '/buses/linevariants';
      cacheSeconds = 86_400;
    } else if (url.pathname.startsWith('/api/linevariants/')) {
      const id = url.pathname.substring('/api/linevariants/'.length);
      if (!/^[A-Za-z0-9_-]+$/.test(id)) {
        return errorResponse(400, 'Identificador de variante inválido.');
      }
      upstreamPath = `/buses/linevariants/${id}`;
      cacheSeconds = 86_400;
    } else if (url.pathname === '/api/busstops') {
      upstreamPath = '/buses/busstops';
      cacheSeconds = 86_400;
    } else {
      const stop = url.pathname.match(/^\/api\/busstops\/(\d+)\/lines$/);
      const upcoming = url.pathname.match(
        /^\/api\/busstops\/(\d+)\/upcomingbuses$/,
      );
      if (stop) {
        upstreamPath = `/buses/busstops/${stop[1]}/lines`;
        cacheSeconds = 86_400;
      } else if (upcoming) {
        upstreamPath =
          `/buses/busstops/${upcoming[1]}/upcomingbuses?${safeUpcomingQuery(url)}`;
        cacheSeconds = 10;
      } else {
        return errorResponse(404, 'Ruta no encontrada.');
      }
    }

    const cacheKey = new Request(`${url.origin}${url.pathname}${url.search}`);
    const cache = caches.default;
    if (cacheSeconds > 0) {
      const cached = await cache.match(cacheKey);
      if (cached) return cached;
      const response = await stmFetch(upstreamPath, env);
      if (!response.ok) {
        return errorResponse(502, `STM respondió HTTP ${response.status}.`);
      }
      let result;
      if (url.pathname === '/api/buses') {
        const payload = await response.json();
        result = new Response(JSON.stringify(busesAsGeoJson(payload)), {
          status: 200,
          headers: corsHeaders(),
        });
        result.headers.set('Cache-Control', `public, max-age=${cacheSeconds}`);
      } else {
        result = copyResponse(response, cacheSeconds);
      }
      ctx.waitUntil(cache.put(cacheKey, result.clone()));
      return result;
    }
    const response = await stmFetch(upstreamPath, env);
    return copyResponse(response);
  } catch (error) {
    console.error(error);
    return errorResponse(502, error instanceof Error ? error.message : 'Error del servicio.');
  }
}

export default {
  fetch(request, env, ctx) {
    return handle(request, env, ctx);
  },
};
