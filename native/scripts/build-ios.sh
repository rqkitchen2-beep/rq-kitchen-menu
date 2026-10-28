#!/bin/bash
# Build a Capacitor iOS app ($APP = customer|driver|branch|cashier) and upload it to App Store Connect.
set -o pipefail
step(){ echo "STEP: $*"; }
die(){ echo "ERROR: $*"; exit 1; }
ROOT="$(pwd)"; DIR="$ROOT/native/$APP"
[ -n "$ASC_KEY" ] || die "secret ASC_KEY missing"
[ -n "$TEAM_ID" ] || die "team id missing"
KEYDIR="$HOME/.appstoreconnect/private_keys"; mkdir -p "$KEYDIR"
KEY="$KEYDIR/AuthKey_${ASC_KEY_ID}.p8"; printf '%s\n' "$ASC_KEY" > "$KEY"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER")

step "select xcode"
XC=$(ls -d /Applications/Xcode_*.app 2>/dev/null | grep -v -i beta | sort -V | tail -1)
[ -n "$XC" ] && sudo xcode-select -s "$XC"
xcodebuild -version

step "npm install"
cd "$DIR" || die "no dir $DIR"
npm install --no-audit --no-fund || die "npm install failed"
npx cap --version

step "prepare www"
python3 "$ROOT/native/scripts/prepare-www.py" "$APP" || die "prepare www failed"
ls www | head -50

step "cap add ios"
rm -rf ios
npx cap add ios || die "cap add ios failed"
npx cap sync ios || die "cap sync failed"

APPDIR="$DIR/ios/App"
PLIST="$APPDIR/App/Info.plist"
PB=/usr/libexec/PlistBuddy
step "patch Info.plist"
setp(){ $PB -c "Delete :$1" "$PLIST" >/dev/null 2>&1; $PB -c "Add :$1 $2 $3" "$PLIST"; }
NAME=$(python3 -c "import json;print(json.load(open('$DIR/capacitor.config.json'))['appName'])")
setp CFBundleDisplayName string "$NAME"
setp ITSAppUsesNonExemptEncryption bool false
setp CFBundleDevelopmentRegion string ar
$PB -c "Delete :CFBundleLocalizations" "$PLIST" >/dev/null 2>&1
$PB -c "Add :CFBundleLocalizations array" -c "Add :CFBundleLocalizations:0 string ar" -c "Add :CFBundleLocalizations:1 string en" "$PLIST"
$PB -c "Delete :UISupportedInterfaceOrientations" "$PLIST" >/dev/null 2>&1
$PB -c "Add :UISupportedInterfaceOrientations array" -c "Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationPortrait" "$PLIST"
$PB -c "Delete :UISupportedInterfaceOrientations~ipad" "$PLIST" >/dev/null 2>&1
if [ "$APP" = branch ] || [ "$APP" = cashier ]; then
  $PB -c "Add :UISupportedInterfaceOrientations~ipad array" -c "Add :UISupportedInterfaceOrientations~ipad:0 string UIInterfaceOrientationPortrait" -c "Add :UISupportedInterfaceOrientations~ipad:1 string UIInterfaceOrientationPortraitUpsideDown" -c "Add :UISupportedInterfaceOrientations~ipad:2 string UIInterfaceOrientationLandscapeLeft" -c "Add :UISupportedInterfaceOrientations~ipad:3 string UIInterfaceOrientationLandscapeRight" "$PLIST"
  $PB -c "Add :UISupportedInterfaceOrientations:1 string UIInterfaceOrientationLandscapeLeft" -c "Add :UISupportedInterfaceOrientations:2 string UIInterfaceOrientationLandscapeRight" "$PLIST"
fi
if [ "$APP" = customer ]; then
  setp NSLocationWhenInUseUsageDescription string "نستخدم موقعك لتحديد عنوان التوصيل بدقة على الخريطة."
elif [ "$APP" = branch ]; then
  setp NSLocationWhenInUseUsageDescription string "لا يستخدم التطبيق موقعك."
elif [ "$APP" = cashier ]; then
  setp NSLocationWhenInUseUsageDescription string "لا يستخدم التطبيق موقعك."
  setp NSLocalNetworkUsageDescription string "يتصل الكاشير بطابعة الإيصالات على شبكة الفرع لطباعة الفواتير."
else
  setp NSLocationWhenInUseUsageDescription string "نستخدم موقعك لإرسال موقع السائق للعميل أثناء توصيل الطلب."
  setp NSLocationAlwaysAndWhenInUseUsageDescription string "نستخدم موقعك أثناء التوصيل حتى لو كانت الشاشة مقفلة، ليتابع العميل وصول طلبه."
  setp NSLocationAlwaysUsageDescription string "نستخدم موقعك أثناء التوصيل حتى لو كانت الشاشة مقفلة، ليتابع العميل وصول طلبه."
  $PB -c "Delete :UIBackgroundModes" "$PLIST" >/dev/null 2>&1
  $PB -c "Add :UIBackgroundModes array" -c "Add :UIBackgroundModes:0 string location" "$PLIST"
fi

step "localized permission texts"
LOC_EN_WHEN="We use your location to set your delivery address accurately on the map."
LOC_EN_ALWAYS=""
if [ "$APP" = driver ]; then
  LOC_EN_WHEN="We use your location to share the driver's position with the customer during delivery."
  LOC_EN_ALWAYS="We use your location during deliveries, even when the screen is locked, so the customer can follow their order."
elif [ "$APP" = branch ] || [ "$APP" = cashier ]; then
  LOC_EN_WHEN="This app does not use your location."
fi
mkdir -p "$APPDIR/App/en.lproj" "$APPDIR/App/ar.lproj"
{
  echo "\"CFBundleDisplayName\" = \"$NAME\";"
  echo "\"NSLocationWhenInUseUsageDescription\" = \"$LOC_EN_WHEN\";"
  [ "$APP" = cashier ] && echo "\"NSLocalNetworkUsageDescription\" = \"The cashier connects to the branch receipt printer on the local network.\";"
  [ -n "$LOC_EN_ALWAYS" ] && echo "\"NSLocationAlwaysAndWhenInUseUsageDescription\" = \"$LOC_EN_ALWAYS\";" && echo "\"NSLocationAlwaysUsageDescription\" = \"$LOC_EN_ALWAYS\";"
} > "$APPDIR/App/en.lproj/InfoPlist.strings"
python3 - "$PLIST" "$APPDIR/App/ar.lproj/InfoPlist.strings" <<'PY'
import plistlib,sys
d=plistlib.load(open(sys.argv[1],'rb'))
keys=['CFBundleDisplayName','NSLocalNetworkUsageDescription','NSLocationWhenInUseUsageDescription','NSLocationAlwaysAndWhenInUseUsageDescription','NSLocationAlwaysUsageDescription']
with open(sys.argv[2],'w') as f:
    for k in keys:
        if k in d: f.write('"%s" = "%s";\n'%(k,d[k].replace('"','\\"')))
PY
cat > "$RUNNER_TEMP/loc.rb" <<'RB'
require 'xcodeproj'
p = Xcodeproj::Project.open(ARGV[0])
t = p.targets.find { |x| x.name == 'App' }
g = p.main_group.find_subpath('App', false)
vg = g.new_variant_group('InfoPlist.strings')
%w[en ar].each { |l| r = vg.new_reference("#{l}.lproj/InfoPlist.strings"); r.name = l }
t.resources_build_phase.add_file_reference(vg)
p.root_object.known_regions = (p.root_object.known_regions + %w[en ar]).uniq
p.save
RB
ruby "$RUNNER_TEMP/loc.rb" "$APPDIR/App.xcodeproj" && echo "RESULT: localized InfoPlist en/ar" || echo "RESULT: WARNING localization skipped"

step "alert sound"
cp "$ROOT/native/sounds/rq_alert.wav" "$APPDIR/App/rq_alert.wav"
cat > "$RUNNER_TEMP/snd.rb" <<'RB'
require 'xcodeproj'
p = Xcodeproj::Project.open(ARGV[0])
t = p.targets.find { |x| x.name == 'App' }
g = p.main_group.find_subpath('App', false)
r = g.new_reference('rq_alert.wav')
t.resources_build_phase.add_file_reference(r)
p.save
RB
ruby "$RUNNER_TEMP/snd.rb" "$APPDIR/App.xcodeproj" && echo "RESULT: alert sound bundled" || echo "RESULT: WARNING alert sound skipped"

step "push delegate"
python3 - "$APPDIR/App/AppDelegate.swift" <<'PY' || die "AppDelegate patch failed"
import sys
p=sys.argv[1]; s=open(p).read()
add = """
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }
"""
if "didRegisterForRemoteNotificationsWithDeviceToken" not in s:
    i = s.rindex("}")
    s = s[:i] + add + s[i:]
open(p,"w").write(s)
PY
echo "RESULT: plugins $(python3 -c "import json;print(','.join(json.load(open('$APPDIR/App/capacitor.config.json')).get('packageClassList',[])))")"

step "icons"
ICONSET="$APPDIR/App/Assets.xcassets/AppIcon.appiconset"
for f in "$ICONSET"/*.png; do cp "$DIR/assets/icon.png" "$f"; done
for f in "$APPDIR"/App/Assets.xcassets/Splash.imageset/*.png; do cp "$DIR/assets/splash.png" "$f"; done
ls "$ICONSET"

step "signing settings"
[ -n "$CERT_ID" ] || die "certificate id missing"
BUNDLE=$(python3 -c "import json;print(json.load(open('$DIR/capacitor.config.json'))['appId'])")
python3 -m venv "$RUNNER_TEMP/venv" && "$RUNNER_TEMP/venv/bin/pip" install -q pyjwt cryptography || die "pip failed"
export ASC_KEY_PATH="$KEY"
P=$(printf '%s' "$ASC_KEY" | shasum -a 256 | cut -c1-40)
OSSL=/opt/homebrew/opt/openssl@3/bin/openssl; [ -x "$OSSL" ] || OSSL=openssl
"$OSSL" enc -d -aes-256-cbc -pbkdf2 -in "$RUNNER_TEMP/cert/dist.p12.enc" -out "$RUNNER_TEMP/dist.p12" -pass "pass:$P" || die "cert decrypt failed"
KC="$RUNNER_TEMP/build.keychain-db"
security create-keychain -p ci "$KC"
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p ci "$KC"
security import "$RUNNER_TEMP/dist.p12" -k "$KC" -P "$P" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild || die "keychain import failed"
security set-key-partition-list -S apple-tool:,apple: -s -k ci "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
security find-identity -v -p codesigning "$KC"
PROF_OUT=$("$RUNNER_TEMP/venv/bin/python" "$ROOT/native/scripts/signing.py" make-profile "$BUNDLE" "$CERT_ID" "$RUNNER_TEMP/app.mobileprovision") || die "profile failed"
PROF_UUID=${PROF_OUT%%|*}; PROF_NAME=${PROF_OUT#*|}
echo "profile: $PROF_NAME ($PROF_UUID)"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$RUNNER_TEMP/app.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROF_UUID.mobileprovision"
PBX="$APPDIR/App.xcodeproj/project.pbxproj"
cat > "$APPDIR/App/App.entitlements" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>aps-environment</key><string>production</string></dict></plist>
ENT
# Apple Pay: only when the profile carries merchant IDs (merchant linked to the app ID in
# the developer portal); otherwise signing would fail, so the app builds without it.
security cms -D -i "$RUNNER_TEMP/app.mobileprovision" > "$RUNNER_TEMP/prof.plist" 2>/dev/null
MIDS=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.in-app-payments" "$RUNNER_TEMP/prof.plist" 2>/dev/null | grep -o 'merchant\.[A-Za-z0-9.-]*' | tr '\n' ' ')
if [ -n "$MIDS" ]; then
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.in-app-payments array" "$APPDIR/App/App.entitlements"
  /usr/libexec/PlistBuddy -c "Add :RQMerchantIds array" "$PLIST" 2>/dev/null
  i=0; for m in $MIDS; do
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.in-app-payments:$i string $m" "$APPDIR/App/App.entitlements"
    /usr/libexec/PlistBuddy -c "Add :RQMerchantIds:$i string $m" "$PLIST"; i=$((i+1)); done
  echo "RESULT: Apple Pay enabled ($MIDS)"
else
  echo "RESULT: Apple Pay not in profile (link merchant ID to the app ID to enable)"
fi
sed -i '' "s#CODE_SIGN_STYLE = Automatic;#CODE_SIGN_STYLE = Manual; DEVELOPMENT_TEAM = $TEAM_ID; PROVISIONING_PROFILE_SPECIFIER = \"$PROF_NAME\"; CODE_SIGN_ENTITLEMENTS = App/App.entitlements;#g" "$PBX"
sed -i '' -e 's/"iPhone Developer"/"Apple Distribution"/g' -e 's/"Apple Development"/"Apple Distribution"/g' -e 's/= "iPhone Developer";/= "Apple Distribution";/g' "$PBX"
{ [ "$APP" = branch ] || [ "$APP" = cashier ]; } || sed -i '' "s/TARGETED_DEVICE_FAMILY = \"1,2\";/TARGETED_DEVICE_FAMILY = 1;/g" "$PBX"
grep -E "CODE_SIGN|PROVISIONING|DEVELOPMENT_TEAM" "$PBX" | sort | uniq -c

if [ -d "$APPDIR/App.xcworkspace" ]; then CONT=(-workspace "$APPDIR/App.xcworkspace"); else CONT=(-project "$APPDIR/App.xcodeproj"); fi
BUILD_NO=$(( GITHUB_RUN_NUMBER + 0 ))
VER=$(cat "$DIR/version.txt" 2>/dev/null || echo 1.0)

step "archive"
xcodebuild "${CONT[@]}" -scheme App -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$RUNNER_TEMP/App.xcarchive" archive \
  MARKETING_VERSION="$VER" CURRENT_PROJECT_VERSION="$BUILD_NO" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KC" | grep -vE "^(CompileC|Ld |    cd |    export |    /Applications|CpResource|ProcessInfoPlist|CopySwiftLibs|Touch |PhaseScript|CompileSwift|SwiftDriver|SwiftCompile|SwiftEmit|EmitSwift|WriteAuxiliary|MkDir|ProcessProductPackaging|CodeSign |GenerateDSYM|RegisterExecutionPolicy|Validate|Copy |CreateBuildDirectory|ClangStatCache|SwiftMergeGeneratedHeaders)" 
[ ${PIPESTATUS[0]} -eq 0 ] || die "archive failed"

step "export + upload"
cat > "$RUNNER_TEMP/export.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Apple Distribution</string>
<key>provisioningProfiles</key><dict><key>$BUNDLE</key><string>$PROF_NAME</string></dict>
<key>teamID</key><string>$TEAM_ID</string>
<key>uploadSymbols</key><true/>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PL
xcodebuild -exportArchive -archivePath "$RUNNER_TEMP/App.xcarchive" -exportOptionsPlist "$RUNNER_TEMP/export.plist" \
  -exportPath "$RUNNER_TEMP/export" "${AUTH[@]}" || die "export/upload failed"
echo "RESULT: uploaded $APP version $VER build $BUILD_NO"
