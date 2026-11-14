PREFIX ?= $(HOME)/.local
.PHONY: build run test install-cli
build:
	./scripts/build.sh
run: build
	open .build/Build/Products/Release/Verbatim.app
test:
	./scripts/test.sh
install-cli: build
	mkdir -p "$(PREFIX)/bin"
	ln -sf "$(CURDIR)/.build/Build/Products/Release/verbatim" "$(PREFIX)/bin/verbatim"
