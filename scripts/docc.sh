xcodebuild docbuild -scheme ax-kit-Package -destination 'generic/platform=macOS' -derivedDataPath "$PWD/.derivedData"
$(xcrun --find docc) process-archive \
  transform-for-static-hosting "$PWD/.derivedData/Build/Products/Debug/AXKit.doccarchive" \
  --output-path docs \
  --hosting-base-path "ax-kit"

echo "<script>window.location.href += \"/documentation/axkit\"</script>" > docs/index.html;
