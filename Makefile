NAME := RyukSign
PLATFORM := iphoneos
SCHEMES := RyukSign
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)
CERT_JSON_URL := https://ryuksign-install.ryuksign.workers.dev/pack.json

.PHONY: all deps clean $(SCHEMES)

all: $(SCHEMES)

clean:
	rm -rf $(TMP)
	rm -rf packages
	rm -rf Payload

deps:
	rm -rf deps || true
	mkdir -p deps

	@if curl -fsSL "$(CERT_JSON_URL)" -o cert.json; then \
	    jq -r '.cert, .ca' cert.json > deps/server.crt; \
	    jq -rj '.key1, .key2' cert.json > deps/server.pem; \
	    jq -r '.info.domains.commonName' cert.json > deps/commonName.txt; \
	else \
	    echo "warning: $(CERT_JSON_URL) unavailable, building without a bundled certificate"; \
	fi

$(SCHEMES): deps
	xcodebuild \
	    -project RyukSign.xcodeproj \
	    -scheme "$@" \
	    -configuration Release \
	    -arch arm64 \
	    -sdk $(PLATFORM) \
	    -derivedDataPath $(TMP) \
	    -skipPackagePluginValidation \
	    CODE_SIGNING_ALLOWED=NO \
	    ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO

	rm -rf Payload
	rm -rf $(STAGE)/
	mkdir -p $(STAGE)/Payload

	mv "$(APP)/$@.app" "$(STAGE)/Payload/$@.app"

	chmod -R 0755 "$(STAGE)/Payload/$@.app"
	codesign --force --sign - --timestamp=none "$(STAGE)/Payload/$@.app"

	cp deps/* "$(STAGE)/Payload/$@.app/" || true

	rm -rf "$(STAGE)/Payload/$@.app/_CodeSignature"
	ln -sf "$(STAGE)/Payload" Payload
	
	mkdir -p packages
	zip -r9 "packages/$@.ipa" Payload
