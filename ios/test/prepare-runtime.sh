#!/bin/sh
set -eu

app_path="$TARGET_BUILD_DIR/$WRAPPER_NAME"
runtime_path="$app_path/perl5"
frameworks_path="$app_path/Frameworks"

rm -rf "$runtime_path" "$frameworks_path/ios.framework" "$frameworks_path/libperl.dylib"
mkdir -p "$runtime_path" "$frameworks_path"
cp -R "$PERL_DIST_PATH/$PERL_VERSION" "$runtime_path/"
cp -R "$PERL_DIST_PATH/site_perl" "$runtime_path/"
mv "$runtime_path/$PERL_VERSION/darwin-thread-multi-2level/CORE/libperl.dylib" "$frameworks_path/"
rm -rf "$runtime_path/$PERL_VERSION/darwin-thread-multi-2level/CORE/libperl.dylib.dSYM"
cp -R "$IOS_FRAMEWORK_PATH/ios.framework" "$frameworks_path/"

exec "$MACOS_PERL_PATH" "$PROJECT_DIR/fix_ios_dylibs.pl" \
    "$PRODUCT_NAME" "$TARGET_BUILD_DIR" "$TARGET_NAME" \
    "$PERL_INSTALL_PREFIX" "$EXPANDED_CODE_SIGN_IDENTITY" "$app_path"
