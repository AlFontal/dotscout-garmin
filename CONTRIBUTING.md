# Contributing to Dotscout

How the face is built, tested and released. For what it does and how to set it up as a user, see the [README](README.md).

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

### Mock scenarios

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

### Sideloading a personal build

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

## How data arrives

- **Nightscout**: the site URL plus a read-only token. IOB, COB and basal come from `/api/v2/properties` when a loop uploads them; otherwise those fields show `--`.
- **xDrip+**: the face reads `http://127.0.0.1:17580/sgv.json` through the phone (xDrip Web Server on, Open Web Service off).
- **AndroidAPS**: the face reads `http://127.0.0.1:28891/sgv.json` from the Garmin plugin.

Connect IQ lets a watch face's background service run at most once every 5 minutes, in about 61 KB of memory; a response that doesn't fit fails with -402 or -403. Many feeds upload a reading every minute, so 3 h from the v1 entries API is about 55 KB, which doesn't fit. Regular runs fetch only the latest 12 entries (about 4 KB). They take the reading closest to each 5-minute slot, and the face merges them into the history it has stored. The delta is the uploader's own value when it sends one (on 1-minute Nightscout feeds that is already a smoothed 5-minute delta); otherwise it is the change from the reading about 5 minutes earlier. When the stored history is mostly empty (after install or a long gap), Nightscout runs also backfill 3 h from the v3 API with only `date,sgv` projected: 180 entries are about 6 KB and peak at about 44 KB of background memory. So the graph is full on the first fetch. v3 needs a token: the face exchanges the access token for a JWT and caches it until it expires. The service also records the source's cadence (median seconds between readings). Runs are timed for just after the next reading is expected, so the face usually lags the sensor by seconds.

On failure the service exits with an error kind (`CgmConfig.ERR_*`) and a code, and the face turns the kind into text in the watch's language.

Credits: the xDrip+ Local Web Services documentation, and the setup notes in swissalpine's GARMIN-xDrip-Spike-Nightscout-Watchface. That project publishes no source or license, so no code was copied from it.

## Design

"F · Dots", everything on black with no panels:

- Status row: Bluetooth (only while the phone is connected) and battery, then the date.
- The time as a 5 × 7 dot matrix of anti-aliased circles (`GLYPHS` in `source/CgmFaceView.mc`), with a dotted divider below it.
- Glucose row: reading age (clock and minutes, e.g. 12') at the value's top left, the value, a trend arrow drawn with the digits' stroke (flat, 45°, vertical, or double above 3 mg/dL per minute), then the change, vertically centred on the value in the same glucose-state colour.
- The 3 h graph: one dot per 5-minute reading between dotted low and high lines, coloured by range. Its scale fits the readings and always includes both lines, with 10% padding rounded out to 10 mg/dL, so a spike or a deep low is drawn at its real height. Dots are as large as their spacing allows.
- Four data fields, in a column beside the tall graph or a row below the classic one: a grey icon, the value and a muted unit.
- The bottom field, heart rate by default, whose heart beats while the watch is awake.

Colour only ever means glucose; everything else is white or grey. Vertical spacing follows the time's 13 px dot pitch, with extra room around the large glucose digits. All colours live in `Palette` in `source/CgmModel.mc`.

**Always-on** keeps only the time as smaller dots, the glucose row and a taller, narrower graph, centred in the space below the time. The status row, date, data fields, heart rate and the divider are hidden, and the face shifts a few pixels each minute against burn-in; the graph's corners clear the round edge at every shift. It measures under 8% lit pixels in the simulator, within the AMOLED budget of about 10%.

### Screen sizes

The layout is written in design units on the 454 px design and scaled to the screen only where it is drawn (`sc()` in `source/CgmFaceView.mc`); text widths come back in design units. At 454 px the scale is exactly 1 and every coordinate stays a whole number, so those watches render exactly as designed. Supported devices are round AMOLED watches with Garmin's vector fonts, at 454, 416, 390 and 360 px. MIP watches (fēnix 7, Forerunner 255/955, Instinct) would need their own colours and layout.

### Fonts, icons and languages

- **Fonts**: the watch's own vector fonts, so text renders smoothly at any size. Bionic Bold, Garmin's sporty face, sets the numbers and the date; Roboto Condensed sets the smaller labels. Watches without Bionic fall back face by face (`NUM_FACES` in `source/CgmFaceView.mc`): the FR970 and FR570 use Roboto Condensed Bold, and the Venu 3, which has no bold Latin face, uses Roboto Regular restamped 1–2 px as a faux bold. Fallback faces are scaled so their digits are as tall as Bionic's, so the layout is identical. Connect IQ's `getVectorFont` size is the full line height (ascender + descender), so the face converts from em sizes and places text by its baseline.
- **Icons**: vector shapes on a 28-unit grid in `source/Icons.mc`, so every field's icon scales to its slot with the same stroke weight (no third-party icon set or license). `tools/gen_assets.py` draws only the launcher icon and the dot-grid brand mark.
- **Languages**: English and Spanish. Every text the face draws or the settings show comes from `resources/strings/strings.xml`, with the Spanish in `resources-spa/strings/strings.xml`.

## Adding a data field

1. Add an id to the enum in `source/Fields.mc` (append it so stored settings keep their meaning) and a case in `Fields.value()` returning `[icon key, value, unit]`. Draw its icon in `source/Icons.mc`.
2. Add a `<listEntry>` for it under each of the five field settings in `resources/settings/settings.xml`.
3. Add its name to `resources/strings/strings.xml` and `resources-spa/strings/strings.xml`.

## Store images

`python3 tools/store_shots.py` renders the store icon, hero image, screenshots and the device sheet (`docs/store/`) in the simulator. It builds a patched copy of the project for each shot (fixed time, demo data, sample field values) and crops each watch screen using the SDK's display rectangle. `docs/store-listing.md` holds the listing text in English and Spanish and says which image goes where.

## Releases

Every version must be signed with the same developer key. `DEVKEY` overrides the key path.

**Beta** (a separate private app in the store, under its own app id, so the public listing's id stays free):

```bash
tools/beta.sh
```

The script bumps the patch version (or sets `VERSION=1.0.0 tools/beta.sh`) and commits it. It exports `dist/CgmFace-<version>-beta.iq` without the personal overrides, then opens the developer site and shows the file in Finder. Set `APP_ID` in a git-ignored `.beta.env` to open the beta's own page. On the phone, the Connect IQ app > My Device > Dotscout > Install.

**Public**:

```bash
RELEASE=public VERSION=1.2.0 tools/beta.sh
```

This builds `dist/CgmFace-<version>.iq` under the manifest's app id. Garmin has no upload API: on the app's page in the developer dashboard, choose Upload New Version. Then tag the release, so CI attaches the signed package to a GitHub release:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

## Continuous integration

`.github/workflows/build.yml` compiles the face for every supported watch on each push and pull request. `.github/workflows/release.yml` runs when a tag such as `v1.1.0` is pushed: it checks the tag matches the manifest version, builds the signed store package and attaches it to a GitHub release.

CI installs the SDK and devices with the community [connect-iq-sdk-manager](https://github.com/lindell/connect-iq-sdk-manager-cli) CLI (`.github/actions-setup.sh`), because Garmin only serves device files to a signed-in account. The repository needs:

| Name | Kind | Value |
| --- | --- | --- |
| `GARMIN_USERNAME`, `GARMIN_PASSWORD` | Secrets | A Garmin account that can download the SDK |
| `CIQ_AGREEMENT_HASH` | Variable | The acceptance hash printed by `connect-iq-sdk-manager agreement view` after you read Garmin's SDK agreement |
| `DEVELOPER_KEY_BASE64` | Secret | The store app's developer key, `base64 -i developer_key` (release only) |

Pull requests from forks get no secrets, so their build check is skipped. Without the secrets the build workflow skips its build steps and still passes, so check that a run actually built.
