APP_NAME := DynamicIslandMac
DIST_DIR := dist.noindex
CODE_SIGN_IDENTITY ?=
SWIFT_BUILD_ENV := CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/module-cache
SWIFT_BUILD_FLAGS := --disable-sandbox --manifest-cache local --cache-path $(CURDIR)/.build/swiftpm-cache --config-path $(CURDIR)/.build/swiftpm-config --security-path $(CURDIR)/.build/swiftpm-security

.PHONY: build package install run verify launch launch-verify logs clean stop quit status

build:
	mkdir -p .build/module-cache .build/swiftpm-cache .build/swiftpm-config .build/swiftpm-security
	$(SWIFT_BUILD_ENV) swift build $(SWIFT_BUILD_FLAGS)

package:
	CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" ./script/package_app.sh

install: package
	ditto $(DIST_DIR)/$(APP_NAME).app /Applications/$(APP_NAME).app

run:
	./script/build_and_run.sh

verify:
	./script/build_and_run.sh --verify

launch:
	./script/launch.sh

launch-verify:
	./script/launch.sh --verify

logs:
	./script/build_and_run.sh --logs

stop:
	-pkill -x $(APP_NAME)

quit: stop

status:
	pgrep -x $(APP_NAME)

clean:
	swift package clean
	rm -rf dist dist.noindex
