# Store listing

Text and images for the Connect IQ Store page, in English and Spanish. The images are in `docs/store/` and are rendered by `tools/store_shots.py`:

- `store-icon-500.png`: the store icon, the face itself on slate. Garmin asks for 500 × 500 px sRGB with about 10 px of padding, on a solid background that is neither transparent nor black.
- `hero-1440x720.png`: the hero image, three watches on slate and no text, so one image serves both languages.
- Screenshots, 454 × 454: `1-in-range.png` (tall layout), `2-rising-classic.png` (classic layout), `3-low-tinted-mmol.png` (low, in mmol/L, minutes tinted) and `4-always-on.png`.
- `all-devices.png`: the face on each supported watch, for the README and the description.

`icon-512.png` is the dot-grid brand mark from `tools/gen_assets.py`, used for the launcher icon and on GitHub, not in the store.

## Title

Dotscout: Nightscout CGM face

## Description (English)

Dotscout is a watch face for people with diabetes that puts your continuous glucose reading next to the time, drawn in dots.

- Glucose coloured by range, with a trend arrow, the 5-minute change and how many minutes old the reading is.
- A 3-hour graph of your readings between your low and high lines, scaled to fit them, so a spike or a deep low shows at its real height. The tall layout (the default) gives the graph more height, with the data fields in a column beside it; the classic layout puts them in a row below.
- The time as a large dot matrix, in white or tinted by your glucose range.
- Four data fields and a bottom field: steps, elevation gain, Body Battery, temperature and heart rate by default, or insulin on board, carbs on board and basal rate from your loop, battery, calories, VO2 max, stress, floors and active minutes.
- An always-on mode with a taller graph that stays within the AMOLED burn-in limits.
- mg/dL or mmol/L, in English or Spanish.
- For round AMOLED watches: Forerunner, fēnix, epix, Venu, vívoactive, MARQ and D2 models from 360 to 454 px.

Works with any CGM that uploads to Nightscout, such as Dexcom or FreeStyle Libre, and with xDrip+ (local web server) and AndroidAPS (Garmin plugin). Readings arrive through the Garmin Connect app on your phone, every 5 minutes.

Set your Nightscout URL and token in this face's settings in the Connect IQ app. Thresholds can be entered in mg/dL or mmol/L.

Questions, problems or ideas: https://github.com/AlFontal/dotscout-garmin/issues

This face is not a medical device. Don't use it to make treatment decisions; always check your CGM app or meter.

## Descripción (español)

Dotscout es una esfera para personas con diabetes que pone tu lectura de glucosa continua junto a la hora, dibujada con puntos.

- La glucosa coloreada según el rango, con flecha de tendencia, el cambio en 5 minutos y los minutos que tiene la lectura.
- Una gráfica de 3 horas con tus lecturas entre tus límites bajo y alto, ajustada a ellas para que un pico o una hipo profunda se vean a su altura real. El diseño alto (el predeterminado) da más altura a la gráfica, con los datos en una columna a su lado; el clásico los pone en una fila debajo.
- La hora como una gran matriz de puntos, en blanco o teñida según tu rango de glucosa.
- Cuatro datos y un dato inferior: pasos, ascenso, Body Battery, temperatura y frecuencia cardiaca por defecto, o insulina activa, carbohidratos activos y basal de tu sistema de lazo, batería, calorías, VO2 máx., estrés, pisos y minutos de intensidad.
- Un modo siempre activo con una gráfica más alta, dentro de los límites contra el quemado de las pantallas AMOLED.
- mg/dL o mmol/L, en español o en inglés.
- Para relojes redondos AMOLED: modelos Forerunner, fēnix, epix, Venu, vívoactive, MARQ y D2 de 360 a 454 px.

Funciona con cualquier MCG que suba a Nightscout, como Dexcom o FreeStyle Libre, y con xDrip+ (servidor web local) y AndroidAPS (plugin de Garmin). Las lecturas llegan cada 5 minutos a través de la app Garmin Connect de tu teléfono.

Configura la URL y el token de Nightscout en los ajustes de esta esfera, en la app Connect IQ. Los umbrales se pueden introducir en mg/dL o mmol/L.

Preguntas, problemas o ideas: https://github.com/AlFontal/dotscout-garmin/issues

Esta esfera no es un producto sanitario. No la uses para tomar decisiones de tratamiento; comprueba siempre tu app de MCG o tu glucómetro.

## FAQ

**It says "Set your Nightscout URL".** Open the Connect IQ app on your phone, find Dotscout under your watch faces, open its settings and enter your site, such as `https://example.herokuapp.com`, without `/api` at the end.

**It says "Token refused".** Create a token in Nightscout under Admin Tools, with the `readable` role, and paste the whole token (it looks like `name-1234567890abcdef`). Public sites don't need one, but the 3-hour backfill after install does.

**How do I use it with xDrip+?** In xDrip+, enable Settings > Inter-app settings > xDrip Web Service, then set Dotscout's data source to xDrip+. For AndroidAPS, enable the Garmin plugin in Config Builder and choose AndroidAPS.

**Why does the reading lag or only update every 5 minutes?** Connect IQ lets a watch face fetch in the background at most once every 5 minutes. Dotscout times each fetch for just after your next reading is expected, so it's usually only seconds behind your CGM.

**The graph is empty after installing.** With a Nightscout token, the face backfills 3 hours on its first fetch. Without one it fills in over 3 hours.

## Privacy

Your Nightscout URL and token are stored only in this face's settings, on your phone and watch. The face sends them only to the Nightscout site you entered. It collects no analytics and has no other servers.

Tu URL y tu token de Nightscout se guardan solo en los ajustes de esta esfera, en tu teléfono y tu reloj. La esfera solo los envía a la web de Nightscout que hayas introducido. No recoge analíticas ni usa otros servidores.
