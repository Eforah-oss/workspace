.POSIX:
.SILENT:
.PHONY: install uninstall

install: workspace.sh
	cp workspace.sh "${DESTDIR}${PREFIX}/bin/workspace"
	chmod 755 "${DESTDIR}${PREFIX}/bin/workspace"

uninstall:
	rm -f "${DESTDIR}${PREFIX}/bin/workspace"
