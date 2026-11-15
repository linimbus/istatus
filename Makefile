.PHONY: all app debug run dump icon clean install

all: app

app:
	./scripts/build.sh release

debug:
	./scripts/build.sh debug

run: app
	-pkill -x iStatus || true
	open dist/iStatus.app

dump:
	swift build -c release
	.build/release/iStatus --dump

icon:
	./scripts/make-icon.sh

clean:
	swift package clean
	rm -rf dist .build/AppIcon.iconset .build/icon-1024.png .build/make-icon

install: app
	-pkill -x iStatus || true
	rm -rf /Applications/iStatus.app
	cp -R dist/iStatus.app /Applications/iStatus.app
	open /Applications/iStatus.app
