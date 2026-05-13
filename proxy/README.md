# PureVideo Cast Proxy

Lekki serwer HTTP, który pozwala castować filmy (HLS/m3u8) na Chromecasta /
Android TV, kiedy serwer z filmem wymaga nagłówków HTTP (Referer, User-Agent,
Cookie). Chromecast sam nie potrafi wysyłać takich nagłówków — robi to za niego
to proxy.

**Typowe objawy, które naprawia:** „logo aplikacji pojawia się na TV, ale film
się nie uruchamia", w logcat `MediaControlChannel: Invalid Request` /
`MediaQueue Error fetching queue item ids, statusCode 2001`.

Proxy działa w Twojej sieci lokalnej (LAN). Nie wystawiaj go do internetu.

---

## Spis treści

1. [Wymagania](#wymagania)
2. [Wariant A — Docker (polecany na PC codziennego użytku)](#wariant-a--docker-polecany-na-pc-codziennego-użytku)
3. [Wariant B — bez Dockera (polecany na serwer z małą ilością miejsca, np. Chromebook/Ubuntu)](#wariant-b--bez-dockera-polecany-na-serwer-z-małą-ilością-miejsca-np-chromebookubuntu)
4. [Jak wpisać adres proxy w aplikacji PureVideo](#jak-wpisać-adres-proxy-w-aplikacji-purevideo)
5. [Weryfikacja — czy proxy działa](#weryfikacja--czy-proxy-działa)
6. [Zarządzanie](#zarządzanie)
   - [Przeglądanie logów](#przeglądanie-logów)
   - [Zatrzymanie](#zatrzymanie)
   - [Uruchamianie przy starcie systemu](#uruchamianie-przy-starcie-systemu)
   - [Aktualizacja](#aktualizacja)
7. [Rozwiązywanie problemów](#rozwiązywanie-problemów)
8. [Endpointy](#endpointy)
9. [Bezpieczeństwo](#bezpieczeństwo)

---

## Wymagania

- Linux (Mint, Ubuntu, Debian itp.). Na macOS/Windows też zadziała (Docker), ale nie jest to tutaj przedmiotem.
- **Wariant A:** Docker + Docker Compose.
- **Wariant B:** Python 3.9+ (zalecane 3.11 lub 3.12), `pip` i `python3-venv`.
- Telefon / Chromecast / komputer **w tej samej sieci WiFi** (LAN).

**Ile zajmuje miejsca:**
| Wariant | Zużycie dysku |
|---|---|
| Docker (`python:3.12-alpine`) | ~110–140 MB |
| Bez Dockera (venv) | ~40–60 MB |

**Zużycie CPU:** znikome. Podczas seansu HD ~2–5 % na starym Chromebooku. W idle — prawie 0 %.

---

## Wariant A — Docker (polecany na PC codziennego użytku)

### 1. Sklonuj repo i przejdź do katalogu proxy

```bash
git clone https://github.com/telewizorpan0-netizen/purevideo.git
cd purevideo/proxy
```

### 2. Uruchom

```bash
docker compose up -d --build
```

Po chwili:

```bash
docker compose ps
# STATUS powinien być Up / healthy
```

### 3. Sprawdź czy działa

```bash
curl http://localhost:8080/health
# -> ok
```

I z innego urządzenia w LAN (np. laptopa, telefonu):

```bash
curl http://<IP_TWOJEGO_PC>:8080/health
# -> ok
```

Żeby poznać IP komputera w LAN:

```bash
hostname -I | awk '{print $1}'
# np. 192.168.1.42
```

### 4. Pełny adres proxy do wpisania w aplikacji PureVideo

```
http://192.168.1.42:8080
```

(podstaw swoje IP)

---

## Wariant B — bez Dockera (polecany na serwer z małą ilością miejsca, np. Chromebook/Ubuntu)

Zużycie dysku: ~40–60 MB.

### 1. Instalacja

```bash
# Opcjonalnie: zrób porządek, żeby odzyskać miejsce
sudo apt clean
sudo journalctl --vacuum-size=50M

# Zainstaluj venv jeśli brakuje
sudo apt update && sudo apt install -y python3-venv python3-pip
```

### 2. Pobierz kod proxy

```bash
cd ~
git clone https://github.com/telewizorpan0-netizen/purevideo.git
cd purevideo/proxy
```

### 3. Utwórz venv i zainstaluj zależności

```bash
python3 -m venv .venv
.venv/bin/pip install --no-cache-dir -r requirements.txt
```

### 4. Uruchom ręcznie (żeby sprawdzić)

```bash
.venv/bin/python proxy.py
# Powinno pojawić się: Uvicorn running on http://0.0.0.0:8080
```

W drugim terminalu:

```bash
curl http://127.0.0.1:8080/health
# -> ok
```

Zatrzymaj: `Ctrl+C`.

### 5. Uruchamianie w tle — systemd

Plik `proxy/systemd/purevideo-cast-proxy.service` jest już szablonem.

> ⚠️ **Dostosuj ścieżki i użytkownika w pliku** (domyślnie `User=pawel` i
> `WorkingDirectory=/home/pawel/purevideo/proxy`). Jeśli Twoja nazwa użytkownika
> jest inna — popraw.

```bash
# Skopiuj do systemowego katalogu systemd
sudo cp systemd/purevideo-cast-proxy.service /etc/systemd/system/

# Przeładuj konfigurację, włącz przy starcie, uruchom
sudo systemctl daemon-reload
sudo systemctl enable --now purevideo-cast-proxy

# Status
systemctl status purevideo-cast-proxy
```

Od teraz proxy startuje automatycznie przy boot-upie.

---

## Jak wpisać adres proxy w aplikacji PureVideo

1. Otwórz aplikację PureVideo na telefonie.
2. Wejdź w zakładkę **Ustawienia** (dolny pasek nawigacji → ikona koła zębatego).
3. Sekcja **Cast** → *Adres proxy Cast* → wpisz:

   ```
   http://192.168.1.42:8080
   ```

   (podstaw IP swojego serwera).

4. Kliknij **Testuj połączenie** — powinno pokazać „OK".
5. Zapisz.

Jeśli pole będzie puste — castowanie zadziała bezpośrednio (ale jeśli serwer
filmu wymaga nagłówków, skończy się to błędem 403).

---

## Weryfikacja — czy proxy działa

### Test podstawowy

```bash
curl http://<IP_PROXY>:8080/health
# -> ok
```

### Test na prawdziwym m3u8

Najłatwiej z aplikacji: odtwórz film, kliknij ikonę Cast, wybierz Chromecast /
Android TV. Powinien zacząć się odtwarzać w ciągu 2–5 sekund.

W trakcie zajrzyj do logów proxy — powinieneś zobaczyć sekwencję:

```
HLS  200 https://<cdn>/.../master.m3u8   123ms  2340 bajtów
HLS  200 https://<cdn>/.../variant.m3u8  98ms   850 bajtów
SEG  GET 200 https://<cdn>/.../seg0001.ts  87ms
SEG  GET 200 https://<cdn>/.../seg0002.ts  120ms
...
```

Jeśli widzisz `HLS 403` albo `SEG 403` — patrz niżej, sekcja „Rozwiązywanie
problemów".

---

## Zarządzanie

### Przeglądanie logów

**Docker:**

```bash
docker compose logs -f              # live tail
docker compose logs --tail=200      # ostatnie 200 linii
```

**systemd:**

```bash
journalctl -u purevideo-cast-proxy -f                    # live
journalctl -u purevideo-cast-proxy --since "10 min ago"  # ostatnie 10 min
```

### Zatrzymanie

**Docker:**

```bash
docker compose down
```

**systemd:**

```bash
sudo systemctl stop purevideo-cast-proxy
```

### Uruchamianie przy starcie systemu

**Docker:** zrobione przez `restart: unless-stopped` w `docker-compose.yml`
(patrz plik).

**systemd:** zrobione przez `systemctl enable` (patrz wyżej).

### Aktualizacja

**Docker:**

```bash
cd ~/purevideo
git pull
cd proxy
docker compose up -d --build
```

**systemd:**

```bash
cd ~/purevideo
git pull
cd proxy
.venv/bin/pip install --no-cache-dir -r requirements.txt
sudo systemctl restart purevideo-cast-proxy
```

---

## Rozwiązywanie problemów

### `curl: (7) Failed to connect to ... port 8080: Connection refused`

- Czy proxy naprawdę wystartowało? → `docker compose ps` lub `systemctl status purevideo-cast-proxy`
- Firewall? Na Mint/Ubuntu sprawdź: `sudo ufw status`. Dodaj regułę:
  ```bash
  sudo ufw allow 8080/tcp
  ```

### Chromecast łączy się, widać logo, ale film się nie odpala (buferuje w nieskończoność)

1. Patrz na logi proxy (`docker compose logs -f` / `journalctl -u ... -f`).
2. Jeśli brak linii z `HLS 200` — Chromecast w ogóle nie łączy się z proxy. 
   Błąd: w Ustawieniach aplikacji adres proxy jest błędny albo urządzenia są
   w różnych sieciach WiFi. Sprawdź z telefonu: 
   `http://<adres-proxy>/health` przez przeglądarkę na telefonie.
3. Jeśli widzisz `HLS 403` lub `SEG 403` — CDN odrzuca requesty mimo nagłówków.
   Możliwe przyczyny:
   - CDN whitelistuje tylko IP telefonu (nie pomoże; wymagałoby VPN).
   - Brakuje jakiegoś nagłówka. Wyłów z logcat telefonu *wszystkie* nagłówki
     używane przez media_kit przy odtwarzaniu lokalnym i porównaj z listą, 
     którą wysyła aplikacja (w logcat: `[PlayerBloc] Cast via proxy... headers=[...]`).

### `docker compose up` — „no space left on device"

Zrób porządek:

```bash
docker system prune -a
sudo apt clean
```

Jeśli to nie wystarczy — użyj Wariantu B (bez Dockera). Oszczędzi Ci ~100 MB.

### Zbyt wolne ładowanie (długie buferowanie)

Proxy nie jest bottleneckiem — problem jest po stronie upstream CDN-u albo 
Twojego łącza WiFi. Ale sprawdź na wszelki wypadek:

```bash
# Podgląd ruchu do proxy (wymaga root):
sudo ss -tnp 'dport = :8080'
```

---

## Endpointy

| Ścieżka | Opis |
|---|---|
| `GET /` | Strona informacyjna |
| `GET /health` | Healthcheck — zwraca `ok` |
| `GET /hls?u=<b64url>&h=<b64json>` | Pobiera playlistę m3u8 z upstreamu (z nagłówkami z `h`) i zwraca ją z przepisanymi URL-ami, żeby Chromecast też sięgał po segmenty przez proxy |
| `GET /seg?u=<b64url>&h=<b64json>` | Strumieniuje segment / klucz / napisy. Obsługuje `Range` |
| `HEAD /seg?...` | Jak wyżej, ale bez body |
| `GET /probe?u=<URL>&h=<JSON>` | Narzędzie diagnostyczne — sprawdza czy upstream odpowiada 200 |

### Format parametrów

- `u` — URL zakodowany w **base64url bez padding** (RFC 4648 §5).
- `h` — JSON `{"Header1":"val1", "Header2":"val2"}` zakodowany w base64url bez
  padding.

Aplikacja PureVideo robi to sama — nie musisz kodować ręcznie.

---

## Bezpieczeństwo

- **Nie wystawiaj proxy do internetu.** Tylko LAN. Nie ma uwierzytelniania 
  (w LAN uznajemy to za akceptowalne).
- **Nagłówki idą w URL** (w parametrze `h`, base64url-kodowane). To **NIE** 
  jest szyfrowane. W sieci LAN nie jest to dramat, ale jeśli w nagłówkach
  masz tokeny sesji (Cookie) — pamiętaj że trafiają one:
  - do historii accesslogów Twojego proxy,
  - do logów Chromecasta (nie idą do Google — cały transport cast↔TV jest 
    szyfrowany end-to-end przez SDK Cast).
- **Proxy ma `verify=False`** dla TLS (bo niektóre CDN-y mają dziwne 
  certyfikaty IP). W zamian nagłówki uzyskują wymaganą przez CDN sygnaturę
  i przynajmniej sam upstream dalej jest po HTTPS.
- **Nie ustawiaj proxy na publicznym VPS** bez dodania auth (IP allowlist, 
  basic auth). Inaczej każdy w internecie będzie miał darmowego anonimizera.

---

Jakbyś utknął — wklej ostatnie ~50 linii logów proxy + ostatnie ~100 linii 
`adb logcat | grep -i cast`. To wystarczy żeby zdiagnozować problem.
