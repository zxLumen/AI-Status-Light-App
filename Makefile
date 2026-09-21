.PHONY: build bundle run clean

APP := AI Status Light

build:
	swift build -c release

bundle:
	./scripts/bundle.sh

run: bundle
	open "build/$(APP).app"

clean:
	swift package clean
	rm -rf build
