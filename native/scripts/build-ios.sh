#!/bin/bash
# Build a Capacitor iOS app ($APP = customer|driver) and upload it to App Store Connect.
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

step "cap add ios"
rm -rf ios
npx cap add ios || die "cap add ios failed"
npx cap sync ios || die "cap sync failed"

APPDIR="$DIR/ios/App"
PLIST="$APPDIR/App/Info.plist"
PB=/usr/libexec/PlistBuddy
step "patch Info.plist"
setp(){ $PB -c "Delete :$1" "$PLIST" >/dev/null 2>&1; $PB -c "Add :$1 $2 $3" "$PLIST"; }
if [ "$APP" = customer ]; then NAME="RQ Kitchen"; else NAME="RQ Driver"; fi
setp CFBundleDisplayName string "$NAME"
setp ITSAppUsesNonExemptEncryption bool false
setp CFBundleDevelopmentRegion string ar
$PB -c "Delete :CFBundleLocalizations" "$PLIST" >/dev/null 2>&1
$PB -c "Add :CFBundleLocalizations array" -c "Add :CFBundleLocalizations:0 string ar" -c "Add :CFBundleLocalizations:1 string en" "$PLIST"
$PB -c "Delete :UISupportedInterfaceOrientations" "$PLIST" >/dev/null 2>&1
$PB -c "Add :UISupportedInterfaceOrientations array" -c "Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationPortrait" "$PLIST"
$PB -c "Delete :UISupportedInterfaceOrientations~ipad" "$PLIST" >/dev/null 2>&1
if [ "$APP" = customer ]; then
  setp NSLocationWhenInUseUsageDescription string "نستخدم موقعك لتحديد عنوان التوصيل بدقة على الخريطة."
else
  setp NSLocationWhenInUseUsageDescription string "نستخدم موقعك لإرسال موقع السائق للعميل أثناء توصيل الطلب."
  setp NSLocationAlwaysAndWhenInUseUsageDescription string "نستخدم موقعك أثناء التوصيل حتى لو كانت الشاشة مقفلة، ليتابع العميل وصول طلبه."
  setp NSLocationAlwaysUsageDescription string "نستخدم موقعك أثناء التوصيل حتى لو كانت الشاشة مقفلة، ليتابع العميل وصول طلبه."
  $PB -c "Delete :UIBackgroundModes" "$PLIST" >/dev/null 2>&1
  $PB -c "Add :UIBackgroundModes array" -c "Add :UIBackgroundModes:0 string location" -c "Add :UIBackgroundModes:1 string audio" "$PLIST"
fi

step "icons"
ICONSET="$APPDIR/App/Assets.xcassets/AppIcon.appiconset"
for f in "$ICONSET"/*.png; do cp "$DIR/assets/icon.png" "$f"; done
for f in "$APPDIR"/App/Assets.xcassets/Splash.imageset/*.png; do cp "$DIR/assets/splash.png" "$f"; done
ls "$ICONSET"

step "signing settings"
PBX="$APPDIR/App.xcodeproj/project.pbxproj"
sed -i '' "s/CODE_SIGN_STYLE = Automatic;/CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBX"
sed -i '' "s/TARGETED_DEVICE_FAMILY = \"1,2\";/TARGETED_DEVICE_FAMILY = 1;/g" "$PBX"
grep -c "DEVELOPMENT_TEAM = $TEAM_ID" "$PBX"

if [ -d "$APPDIR/App.xcworkspace" ]; then CONT=(-workspace "$APPDIR/App.xcworkspace"); else CONT=(-project "$APPDIR/App.xcodeproj"); fi
BUILD_NO=$(( GITHUB_RUN_NUMBER + 0 ))
VER=$(cat "$DIR/version.txt" 2>/dev/null || echo 1.0)

step "archive"
xcodebuild "${CONT[@]}" -scheme App -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$RUNNER_TEMP/App.xcarchive" archive \
  MARKETING_VERSION="$VER" CURRENT_PROJECT_VERSION="$BUILD_NO" \
  "${AUTH[@]}" | grep -vE "^(CompileC|Ld |    cd |    export |    /Applications|CpResource|ProcessInfoPlist|CopySwiftLibs|Touch |PhaseScript|CompileSwift|SwiftDriver|SwiftCompile|SwiftEmit|EmitSwift|WriteAuxiliary|MkDir|ProcessProductPackaging|CodeSign |GenerateDSYM|RegisterExecutionPolicy|Validate|Copy |CreateBuildDirectory|ClangStatCache|SwiftMergeGeneratedHeaders)" 
[ ${PIPESTATUS[0]} -eq 0 ] || die "archive failed"

step "export + upload"
cat > "$RUNNER_TEMP/export.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM_ID</string>
<key>uploadSymbols</key><true/>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PL
xcodebuild -exportArchive -archivePath "$RUNNER_TEMP/App.xcarchive" -exportOptionsPlist "$RUNNER_TEMP/export.plist" \
  -exportPath "$RUNNER_TEMP/export" "${AUTH[@]}" || die "export/upload failed"
echo "RESULT: uploaded $APP version $VER build $BUILD_NO"
