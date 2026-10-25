import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


TOKEN_URL = (
    "https://mvdapi-auth.montevideo.gub.uy/auth/realms/pci/"
    "protocol/openid-connect/token"
)
BUSES_URL = "https://api.montevideo.gub.uy/api/transportepublico/buses"
SECRET_KEYS = {
    "access_token",
    "refresh_token",
    "client_secret",
    "secret",
    "authorization",
    "token",
}


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key.strip()] = value
    return values


def redact(value: object) -> object:
    if isinstance(value, dict):
        return {
            key: "[REDACTADO]" if key.lower() in SECRET_KEYS else redact(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def get_access_token(credentials: dict[str, str]) -> str:
    client_id = credentials.get("CLIENT_ID", "")
    client_secret = credentials.get("CLIENT_SECRET", "")
    if not client_id or not client_secret:
        raise ValueError(
            "Faltan CLIENT_ID y CLIENT_SECRET en .env. "
            "Usá las credenciales de la aplicación del portal; "
            "un access token temporal no las sustituye."
        )

    body = urllib.parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        }
    ).encode()
    request = urllib.request.Request(
        TOKEN_URL,
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise RuntimeError(
            f"No se pudo obtener el token OAuth (HTTP {error.code}). "
            "Verificá CLIENT_ID, CLIENT_SECRET y la suscripción al servicio."
        ) from None
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError("No se pudo conectar al servicio OAuth.") from None
    if not isinstance(payload, dict) or not isinstance(
        payload.get("access_token"), str
    ):
        raise RuntimeError("La respuesta OAuth no contiene un access_token válido.")
    return payload["access_token"]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verifica una consulta a la API de buses de Montevideo."
    )
    parser.add_argument(
        "--line",
        default="522",
        help="Línea a consultar (por defecto: 522, ejemplo del manual oficial).",
    )
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]{1,12}", args.line):
        parser.error("La línea debe contener solo letras, números o guiones.")

    credentials = load_env(Path(".env"))
    try:
        token = get_access_token(credentials)
    except (ValueError, RuntimeError) as error:
        print(error, file=sys.stderr)
        return 1

    url = f"{BUSES_URL}?{urllib.parse.urlencode({'lines': args.line})}"
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "Rumbo local API smoke test",
        },
    )
    del token
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw_body = response.read()
            status = response.status
            content_type = response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as error:
        print(f"Consulta de buses rechazada (HTTP {error.code}).", file=sys.stderr)
        return 1
    except (urllib.error.URLError, TimeoutError):
        print("No se pudo conectar con la API de transporte.", file=sys.stderr)
        return 1

    print(f"HTTP {status}; Content-Type: {content_type}")
    try:
        payload = json.loads(raw_body)
    except json.JSONDecodeError:
        print("La respuesta no es JSON válido.")
        print(raw_body[:4000].decode("utf-8", errors="replace"))
        return 0
    print(json.dumps(redact(payload), ensure_ascii=False, indent=2)[:12000])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
