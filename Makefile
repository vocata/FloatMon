APP_NAME := DynamicIslandMac

.PHONY: build run verify launch launch-verify logs clean stop quit status

build:
	swift build

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
	rm -rf dist
