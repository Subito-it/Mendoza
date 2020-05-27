prefix ?= /usr/local
bindir = $(prefix)/bin

build:
	swift build -c release --disable-sandbox

install: build
	install ".build/release/Mendoza" "$(bindir)"

uninstall:
	rm -rf "$(bindir)/Mendoza"

clean:
	rm -rf .build

rebuild:
	make uninstall build install

.PHONY: build install uninstall clean
