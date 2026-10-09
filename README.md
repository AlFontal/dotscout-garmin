# Dotscout

A Connect IQ watch face for 454 × 454 AMOLED Garmin watches that puts continuous glucose data next to the time:

- the time as a large dot matrix, white or tinted by your glucose range
- glucose coloured by range, with a trend arrow, the 5-minute change and the reading age
- a 3 h dot graph between dotted low and high lines
- four configurable data fields and one at the bottom (heart rate by default)
- a dim, drifting always-on mode for burn-in protection

Colour only ever means glucose: green in range, amber high, orange very high, red low, grey when the reading is over 15 minutes old. Everything else is white or grey.

## Supported watches

Forerunner 965, 970 and 570 (47 mm), fēnix 8 (47/51 mm, AMOLED) and fēnix 8 Pro, epix Pro (Gen 2) 51 mm, Venu 3, Venu 4 45 mm, D2 Mach 2 and D2 Mach 2 Pro, plus the models that share those device profiles (tactix 7/8, quatix 8, D2 Mach 1 Pro, D2 Air X15). All are 454 × 454 AMOLED.

## Build and run

Needs the Connect IQ SDK (built with 9.1.0) with the target devices installed, and a developer key. Never commit the key; `.gitignore` excludes `*.der` and `*.pem`.

```bash
monkeyc -d fr965 -f monkey.jungle -o bin/CgmFace.prg -y /path/to/developer_key -w
```

```bash
connectiq
```

```bash
monkeydo bin/CgmFace.prg fr965
```

Simulator tips:

- **File > Edit Persistent Storage > Edit Application.Properties data** to set `DataSource` to 0 (demo) and pick a `MockScenario` (0-6).
- **Settings > Low Power Mode** to see the always-on view.

## Install on your watch

Sideloaded apps can't be configured from Garmin Connect, so a personal build bakes the Nightscout settings in. `tools/make-local.sh` writes them to the git-ignored `resources-local/` and `local.jungle`. It reads `NIGHTSCOUT_URL` and `NIGHTSCOUT_TOKEN` from the environment or from a git-ignored `.env`:

```bash
tools/make-local.sh
```

```bash
monkeyc -d fr965 -f "monkey.jungle;local.jungle" -o bin/CgmFace.prg -y /path/to/developer_key
```

1. Install OpenMTP; the FR965 connects over MTP, not as a USB drive.
2. Plug in the watch and copy `bin/CgmFace.prg` into `GARMIN/APPS/`.
3. Unplug, then on the watch hold MENU on the watch face, choose Watch Face, and pick Dotscout.

The watch fetches through the Garmin Connect app on your phone every 5 minutes. The graph fills in over 3 h after install.

## Beta release (over the air)

A private beta in the Connect IQ Store installs over the air from the Connect IQ phone app, and its settings can be changed there, so nothing is baked in.

```bash
tools/beta.sh
```

The script bumps the patch version (or sets `VERSION=1.0.0 tools/beta.sh`) and commits it. It exports `dist/CgmFace-<version>.iq` without the personal overrides, then opens the developer site and shows the file in Finder. Garmin has no upload API, so the rest is manual:

1. On https://apps.garmin.com/en-US/developer/upload, upload the `.iq`. The first time, use Upload an App and tick "Beta app"; after that, open the app from your app list at https://apps.garmin.com/developer/dashboard and upload a new version.
2. On the phone, open the Connect IQ app > My Device > Dotscout > Install, then set the URL and token in its settings.

Set `APP_ID` in a git-ignored `.beta.env` to open the app's own page. `DEVKEY` overrides the key path. Every version must be signed with the same developer key.

## Mock scenarios

With **Data source** set to Demo (`DataSource` = 0) the face draws a deterministic fake feed, so it can be tried without a sensor. `MockScenario` is not a user setting; set it in the simulator.

| `MockScenario` | Scenario |
| --- | --- |
| 0 | Steady in range |
| 1 | Realistic day (default) |
| 2 | Rising fast after a meal |
| 3 | Dropping toward low |
| 4 | Sustained high |
| 5 | Stale, no reading for 25 min |
| 6 | No data |

## Live data

Set **Data source** in the app settings (Connect IQ app on the phone):

- **Nightscout**: your site URL plus a read-only token from Admin Tools > Subjects. IOB, COB and basal come from `/api/v2/properties` when a loop uploads them; otherwise those fields show `--`.
- **xDrip+**: enable Inter-App settings > xDrip Web Server and leave Open Web Service off. The face reads `http://127.0.0.1:17580/sgv.json` through the phone.
- **AndroidAPS**: enable the Garmin plugin in Config Builder. The face reads `http://127.0.0.1:28891/sgv.json`.

Connect IQ lets a watch face's background service run at most once every 5 minutes, in about 61 KB of memory; a response that doesn't fit fails with -402 or -403. Many feeds upload a reading every minute, so 3 h from the v1 entries API is about 55 KB, which doesn't fit. Regular runs fetch only the latest 12 entries (about 4 KB). They take the reading closest to each 5-minute slot, and the face merges them into the history it has stored. The delta is the uploader's own value when it sends one (on 1-minute Nightscout feeds that is already a smoothed 5-minute delta); otherwise it is the change from the reading about 5 minutes earlier. When the stored history is mostly empty (after install or a long gap), Nightscout runs also backfill 3 h from the v3 API with only `date,sgv` projected: 180 entries are about 6 KB and peak at about 44 KB of background memory. So the graph is full on the first fetch. v3 needs a token: the face exchanges the access token for a JWT and caches it until it expires. The service also records the source's cadence (median seconds between readings). Runs are timed for just after the next reading is expected, so the face usually lags the sensor by seconds.

Credits: the xDrip+ Local Web Services documentation, and the setup notes in swissalpine's GARMIN-xDrip-Spike-Nightscout-Watchface. That project publishes no source or license, so no code was copied from it.

## Settings

Set in the Connect IQ phone app (store installs) or baked in by `tools/make-local.sh` (sideloaded builds).

| Setting | Values |
| --- | --- |
| Data source | Nightscout (default), xDrip+ (phone, local), AndroidAPS (phone, local), Demo |
| Nightscout URL, Nightscout token | Your site, and a read-only token (optional for public sites) |
| Units | mg/dL or mmol/L |
| Low threshold, High threshold | In either unit: values under 30 are read as mmol/L (3.9 or 70; 10 or 180) |
| Time colour | White, minutes by glucose, or the whole time by glucose |
| Data fields 1–4, Bottom field | Steps, elevation gain, Body Battery, temperature and heart rate by default; also IOB, COB, basal, battery, calories, VO2 max, stress, floors and weekly active minutes |

12/24-hour time and always-on follow the watch's own settings. Very high starts at 250 mg/dL, and a reading turns grey after 15 minutes.

## Fonts and icons

- **Fonts**: the watch's own vector fonts, so text renders smoothly at any size. Bionic Bold, Garmin's sporty face, sets the numbers; Roboto Condensed sets the labels. Watches without Bionic fall back face by face (`NUM_FACES` in `source/CgmFaceView.mc`): the FR970 and FR570 use Roboto Condensed Bold, and the Venu 3, which has no bold Latin face, uses Roboto Regular restamped 1–2 px as a faux bold. Fallback faces are scaled so their digits are as tall as Bionic's, so the layout is identical. Connect IQ's `getVectorFont` size is the full line height (ascender + descender), so the face converts from em sizes and places text by its baseline.
- **Time**: drawn as a 5 × 7 dot matrix of anti-aliased circles (`GLYPHS` in `source/CgmFaceView.mc`), on the same dot language as the graph and the divider.
- **Icons**: vector shapes in `source/Icons.mc`. Less common fields use white bitmap fallbacks that `tools/gen_assets.py` draws with Pillow (no third-party icon set or license).

Store images and screenshots are in `docs/store/`, including `all-devices.png`, the face on each supported watch.

## Layout

"F · Dots", everything on black with no panels:

- Status row: Bluetooth (only while the phone is connected) and battery, then the date.
- The time as a dot matrix, with a dotted divider below it.
- Glucose on one baseline: the value, a trend arrow drawn with the digits' stroke (flat, 45°, vertical, or double above 3 mg/dL per minute), then the change over the reading age. The change's tops align with the value's caps and the age sits on its baseline.
- The 3 h graph: one dot per 5-minute reading on a 50–230 mg/dL scale between dotted low and high lines, coloured by range, with the latest reading as a larger dot.
- Four data fields: a grey icon, the value and a muted unit.
- The bottom field, heart rate by default, whose heart beats while the watch is awake.

Vertical spacing follows the time's 13 px dot pitch, with extra room around the large glucose digits. All colours live in `Palette` in `source/CgmModel.mc`.

**Always-on** keeps the date, the time as smaller dots, the glucose row and the graph, with the glucose and graph centred in the space below the time. Data fields, heart rate and the divider are hidden, and the face shifts a few pixels each minute against burn-in. It measures about 7% lit pixels in the simulator, within the AMOLED budget of about 10%.

## Data fields

To add one:

1. Add an id to the enum in `source/Fields.mc` (append it so stored settings keep their meaning) and a case in `Fields.value()` returning `[icon key, value, unit]`. Draw the icon in `source/Icons.mc`, or add a bitmap fallback to `ICONS` in `tools/gen_assets.py` (it writes `drawables.xml`).
2. Add a `<listEntry>` for it under each of the five field settings in `resources/settings/settings.xml`.
3. Add its name to `resources/strings/strings.xml`.
