# YuE2 Studio a DGX-en (headless Linux)

A YuE2 Studio egy Windowsra szánt, grafikus asztali alkalmazas (PySide6). A szamitasigenyes
resz viszont egy kulon natív folyamat: az `audiocpp_server`, ami a GPU-n futtatja a modellt.
A GUI ezt a szervert `--host 127.0.0.1 --port 8080`-on inditja, es HTTP API-n (`/health`,
`/v1/...`) beszel vele. A kod kezeli a mar futo kulso szervert is: ha a porton mar felel egy
szerver, a GUI azt hasznalja, nem indit ujat (`server_external`, yue2_studio.py:7733).

Ezert a tiszta megoldas egy fejnelkuli DGX-en: **csak a szervert futtatjuk a DGX-en, a GUI a
sajat gepeden marad, es egy SSH-alaguton keresztul eri el a DGX szerveret.**

## Ajanlott felallas (A ut): szerver a DGX-en, GUI a gepeden

### 1. Szerver-binaris a DGX-re (nincs build)
A felso installer csak Windows CUDA zipet tolt. Linuxra van KESZ binaris az audio.cpp
release-ekben, a yue2-studio altal pinnelt pontos verziohoz is:

- audio.cpp v0.8.1, Ubuntu x64 CUDA:
  `audio-v0.8.1-bin-ubuntu-x64-cuda12.8-colab.tar.gz`
  (https://github.com/0xShug0/audio.cpp/releases/tag/v0.8.1)
- Mellé a CUDA runtime, ha nincs a rendszeren: a megfelelő `...-cudart-ubuntu-x64-cuda...` csomag
  az ujabb release-eknel.

Tomoritsd ki egy mappaba a DGX-en, pl. `~/yue2/motor/`, ugy hogy az `audiocpp_server` binaris
ott (vagy alatta) legyen.

### 2. Modellek a DGX-re
A szerver futasidoben, API-n tolti a modelleket (`POST /v1/models/load`). A GGUF-okat a
HuggingFace-rol szerezd be egy mappaba, pl. `~/yue2/modellek/` (audio-cpp/Yue2-3B-GGUF,
SheetSage2-GGUF stb.). Nagysagrend: YuE2-3B Q4 ~2,7 GB, Q8 ~4 GB, BF16 ~7 GB (+VAE, +SheetSage2
~2,7 GB). Ajanlott VRAM ~16 GB (a DGX-en boven van).

### 3. Szerver inditasa a DGX-en
Ebben a mappaban: `dgx/yue2-dgx-launcher.sh`. A GUI sajat inditasi logikajabol vezetve, de
`--backend cuda`-val (a GUI nem-Windows agon tevesen `metal`-t adna). Nem tolt le es nem buildel
semmit, a binarisnak es a modelleknek mar a helyen kell lenniuk.

```bash
export YUE2_ENGINE_DIR=~/yue2/motor        # ahol az audiocpp_server van
export YUE2_MODELS_DIR=~/yue2/modellek     # ahol a GGUF-ok vannak
export YUE2_GPU=0                          # melyik GPU (ures = mind)
bash dgx/yue2-dgx-launcher.sh
```

Alapbol `127.0.0.1:8080`-ra kot (ez a legbiztonsagosabb, mert a szervernek NINCS
autentikacioja). A preflight kiirja az `nvidia-smi`-t.

### 4. GUI a gepeden -> SSH-alagut a DGX-hez
A GUI bedrotozottan `127.0.0.1:8080`-at keres. Nyiss egy local-forward alagutat, igy a gepeden a
127.0.0.1:8080 a DGX szerveret eri el, es a GUI azt hiszi, helyben fut:

```bash
ssh -N -L 8080:127.0.0.1:8080 <felhasznalo>@<dgx-cim>
```

Ezutan inditsd a GUI-t a sajat gepeden (`python yue2_studio.py`). Az indit-szerver gombot NE
nyomd meg; a GUI eszleli a mar futo szervert az alaguton at.

> Alternativak a GUI 127.0.0.1-kotesere, ha nem akarsz alagutat:
> - egy egysoros patch a `Yue2Api.base`-ben (yue2_studio.py:431), hogy a DGX cimere mutasson;
> - vagy a szerver sajat web-UI-ja (`--ui`) kozvetlenul bongeszobol (a web-UI teljessege nem
>   mert, a flag-ekbol kovetkeztetve).
> Ha a DGX es a geped nem egy megbizhato/zart halon van, maradj az SSH-alagutnal: a szervernek
> nincs sajat autentikacioja, 0.0.0.0-ra kotni kockazatos.

## B ut (nem ajanlott): az egesz app a DGX-en
Ehhez grafikus asztal (X/Wayland vagy VNC) kell a fejnelkuli DGX-en, es a GUI QtWebEngine
(Chromium) + hangkimenet reszei headless kornyezetben torekenyek. A nehez szamitas ugyis a kulon
szerverben van, ezert ennek nincs ertelme az A uttal szemben.

## Osszefoglalva
- A szerver tisztan szetvalaszthato a GUI-tol (a kod maga szamol kulso szerverrel).
- Nincs build: pontos verzioju (v0.8.1) kesz Linux CUDA binaris letezik.
- Egyetlen kerdes a GUI 127.0.0.1-kotese -> SSH-alagut oldja meg, kodmodositas nelkul.
- Munka: nagyjabol fel nap (binaris + modellek letoltese a DGX-re, launcher, alagut).
