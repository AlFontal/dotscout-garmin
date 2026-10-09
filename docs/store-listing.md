# Store listing

Draft text for the Connect IQ Store page. Images are in `docs/store/`: `icon-512.png` and four 454 × 454 screenshots (in range, rising high, low with the minutes tinted, always-on). The screenshots use sample steps and ascent instead of the simulator's zeros.

## Title

Dotscout: Nightscout CGM face

## Description

Dotscout is a watch face for people with diabetes that puts your continuous glucose reading next to the time, drawn in dots.

- Glucose coloured by range, with a trend arrow, the 5-minute change and how old the reading is.
- A 3-hour graph of your readings between your low and high lines.
- The time as a large dot matrix, in white or tinted by your glucose range.
- Four data fields and a bottom field: steps, elevation gain, Body Battery, temperature and heart rate by default, or insulin on board, carbs on board and basal rate from your loop.
- An always-on mode that stays within the AMOLED burn-in limits.

Works with any CGM that uploads to Nightscout, such as Dexcom or FreeStyle Libre, and with xDrip+ (local web server) and AndroidAPS (Garmin plugin). Readings arrive through the Garmin Connect app on your phone, every 5 minutes.

Set your Nightscout URL and token in this face's settings in the Connect IQ app. Thresholds can be entered in mg/dL or mmol/L.

This face is not a medical device. Don't use it to make treatment decisions; always check your CGM app or meter.

## Privacy

Your Nightscout URL and token are stored only in this face's settings, on your phone and watch. The face sends them only to the Nightscout site you entered. It collects no analytics and has no other servers.
