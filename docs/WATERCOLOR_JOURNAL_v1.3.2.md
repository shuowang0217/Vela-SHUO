# Vela v1.3.2 watercolor journal UI

The attached watercolor map is an artistic reference, not a cartographically
registered source. Maps shipped in builds are generated from the already
geo-registered day texture so markers remain aligned.

Run: python scripts/generate_world_watercolor.py
Then: flutter pub get && flutter analyze && flutter test

The default palette is paper-and-ink journal, with independent light / dark
tones. Previous eight palette choices remain available. Shared page cards,
buttons, text, list tiles and forms use the journal visual language. English
city labels are approximated from node titles, not verified IP geolocation.
Network and VPN implementations remain untouched.
