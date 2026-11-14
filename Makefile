PREFIX ?= $(HOME)/.local
APPDIR ?= /Applications
.PHONY: build run test install install-cli
build:
	./scripts/build.sh
run: build
	open .build/Build/Products/Release/Verbatim.app
test:
	./scripts/test.sh
install: build
	mkdir -p "$(APPDIR)"
	rm -rf "$(APPDIR)/Verbatim.app"
	ditto .build/Build/Products/Release/Verbatim.app "$(APPDIR)/Verbatim.app"
install-cli: build
	mkdir -p "$(PREFIX)/bin"
	ln -sf "$(CURDIR)/.build/Build/Products/Release/verbatim" "$(PREFIX)/bin/verbatim"
