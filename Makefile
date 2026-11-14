.PHONY: build run test
build:
	./scripts/build.sh
run: build
	open .build/Build/Products/Release/Verbatim.app
test:
	./scripts/test.sh
