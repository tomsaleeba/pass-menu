INSTALL_PATH = /usr/local/bin/pass-menu
VERSION = v0.0 git

ifndef VERBOSE
.SILENT:
endif

.ONESHELL:

# ----------------------- #
#          BUILD          #
# ----------------------- #
.PHONY: install uninstall

help:
	echo "Pass-Menu $(VERSION)"
	echo
	echo "Targets:"
	echo "  :install         install pass-menu on this system."
	echo "  :uninstall       uninstall pass-menu on this system."
	echo
	echo "Examples:"
	echo "  make install"


install: root-check
	echo :: INSTALLING PASS-MENU
	$(call install, 0755, ./pass-menu.sh,    $(INSTALL_PATH))
	$(call install, 0644, ./man/pass-menu.1, /usr/local/share/man/man1/pass-menu.1)
	echo :: DONE

uninstall: root-check
	echo :: UNINSTALLING PASS-MENU
	$(call remove, $(INSTALL_PATH))
	$(call remove, /usr/local/share/man/man1/pass-menu.1)
	echo :: DONE


# ----------------------- #
#          UTILS          #
# ----------------------- #
root-check:
	if [ `whoami` != "root" ]; then
		echo "please run as root to continue..."
		exit 1
	fi

define success
	echo -e "  \e[1;32m==>\e[0m"
endef

define failure
	echo -e "  \e[1;31m==>\e[0m"
endef

define install 
	if install -m $(1) $(2) $(3) 2> /tmp/make-err; then
		$(success) $(2)
	else
		$(failure) $(2)
		sed "s:^:  :" /tmp/make-err
		rm /tmp/make-err
	fi
endef

define remove
	if rm $(1) 2> /tmp/make-err; then
		$(success) $(1)
	else
		$(failure) $(1)
		sed "s:^:  :" /tmp/make-err
		rm /tmp/make-err
	fi
endef
