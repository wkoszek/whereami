PROJECT=whereami.xcodeproj
SCHEME=whereami
CONFIG=Debug
DERIVED_DIR=$(CURDIR)/DerivedData
IOS_DEST?=generic/platform=iOS Simulator
IOS_SDK?=iphonesimulator
MAC_DEST?=generic/platform=macOS

.PHONY: all ios mac clean

all: ios mac

ios:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(IOS_DEST)' -sdk $(IOS_SDK) -derivedDataPath $(DERIVED_DIR) build

mac:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED_DIR) -sdk macosx CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGN_STYLE=Manual build
	mkdir -p build/mac
	cp -R $(DERIVED_DIR)/Build/Products/$(CONFIG)-macosx/*.app build/mac/ 2>/dev/null || true
	@if ls build/mac/*.app 1> /dev/null 2>&1; then \
		for APP in build/mac/*.app; do \
			echo "Signing $$APP"; \
			codesign --force --deep --sign - --entitlements whereami/whereami.entitlements "$$APP"; \
		done; \
	fi

cmd:
	mkdir -p build/cli
	swiftc -O -parse-as-library ./whereami/LocationModels.swift ./whereami/MacLocationClient.swift ./CLI/main.swift -framework CoreBluetooth -module-cache-path $(DERIVED_DIR)/CLI-ModuleCache -o build/cli/whereami-cli
	codesign --force --sign - --entitlements CLI/cli.entitlements build/cli/whereami-cli

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED_DIR) clean
