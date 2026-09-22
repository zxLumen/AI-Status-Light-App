.PHONY: build bundle icon run install clean

APP := AI Status Light

build:
	swift build -c release

# Regenerate Resources/AppIcon.icns + docs/images/icon-1024.png
icon:
	swift scripts/make-icon.swift

bundle:
	./scripts/bundle.sh

run: bundle
	open "build/$(APP).app"

install: bundle
	rm -rf "/Applications/$(APP).app"
	ditto "build/$(APP).app" "/Applications/$(APP).app"
	@echo "installed: /Applications/$(APP).app"
	open "/Applications/$(APP).app"

clean:
	swift package clean
	rm -rf build
