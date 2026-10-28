#!/bin/bash
# Build the Android APK of a Capacitor app ($APP, e.g. branch), signed with the RQ key.
set -o pipefail
step(){ echo "STEP: $*"; }
die(){ echo "ERROR: $*"; exit 1; }
ROOT="$(pwd)"; DIR="$ROOT/native/$APP"
[ -n "$ASC_KEY" ] || die "secret ASC_KEY missing"
PASS=$(printf '%s' "$ASC_KEY" | tr -d ' \r\n\t' | sha256sum | cut -d' ' -f1)
openssl enc -d -aes-256-cbc -pbkdf2 -in "$ROOT/native/android/rq.jks.enc" -out "$RUNNER_TEMP/rq.jks" -pass pass:$PASS || die "keystore decrypt failed"

step "npm install"
cd "$DIR" || die "no dir"
npm install --no-audit --no-fund || die "npm install failed"
# no Firebase on these devices: drop iOS-only plugins that need it
npm uninstall --no-audit --no-fund @capacitor/push-notifications @capacitor/geolocation >/dev/null 2>&1
npm install --no-audit --no-fund @capacitor/android@latest || die "android platform install failed"

step "prepare www"
python3 "$ROOT/native/scripts/prepare-www.py" "$APP" || die "prepare www failed"

step "cap add android"
rm -rf android
npx cap add android || die "cap add android failed"
npx cap sync android || die "cap sync failed"
grep -o '"classpath": *"[^"]*"' android/app/src/main/assets/capacitor.plugins.json 2>/dev/null | tr '\n' ' ' | sed 's/^/RESULT: plugins /'; echo

step "icon + version"
RES=android/app/src/main/res
rm -rf $RES/mipmap-anydpi-v26
python3 -c "import PIL" 2>/dev/null || pip3 install -q --break-system-packages pillow || pip3 install -q pillow
python3 - "$RES" <<'PY'
import sys, os
from PIL import Image
res = sys.argv[1]; im = Image.open('assets/icon.png').convert('RGBA')
for n, s in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    d = os.path.join(res, 'mipmap-' + n); os.makedirs(d, exist_ok=True)
    for f in ('ic_launcher.png','ic_launcher_round.png'): im.resize((s, s), Image.LANCZOS).save(os.path.join(d, f))
    fg = os.path.join(d, 'ic_launcher_foreground.png')
    if os.path.exists(fg): os.remove(fg)
print('icons ok')
PY
VC=$((GITHUB_RUN_NUMBER + 100))
sed -i "s/versionCode [0-9]*/versionCode $VC/; s/versionName \"[^\"]*\"/versionName \"1.0.$GITHUB_RUN_NUMBER\"/" android/app/build.gradle
# keep the device awake & portrait-friendly; lock to sensor portrait is not forced
sed -i 's#<application#<application android:usesCleartextTraffic="false"#' android/app/src/main/AndroidManifest.xml

step "gradle build"
cd android
chmod +x gradlew
./gradlew --no-daemon assembleRelease 2>&1 | tail -60 || die "gradle failed"
UNS=$(ls app/build/outputs/apk/release/*-unsigned.apk 2>/dev/null | head -1)
[ -f "$UNS" ] || die "no apk"
BT=$(ls -d $ANDROID_HOME/build-tools/* | sort -V | tail -1)
"$BT/zipalign" -f -p 4 "$UNS" "$RUNNER_TEMP/aligned.apk" || die "zipalign failed"
NAME=$(python3 -c "import json;print(json.load(open('$DIR/capacitor.config.json'))['appName'].replace(' ','-'))")
OUT="$RUNNER_TEMP/$NAME.apk"
"$BT/apksigner" sign --ks "$RUNNER_TEMP/rq.jks" --ks-key-alias rq --ks-pass pass:$PASS --key-pass pass:$PASS --out "$OUT" "$RUNNER_TEMP/aligned.apk" || die "sign failed"
"$BT/apksigner" verify "$OUT" && echo "RESULT: apk signed $(du -h "$OUT" | cut -f1) versionCode $VC"
