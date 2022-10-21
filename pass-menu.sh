#!/usr/bin/env bash

set -x
readonly VERSION="v1.0"

MODE=""
MENUCMD=""
TIMEOUT="45"
STOREDIR="${PASSWORD_STORE_DIR-$HOME/.password-store}"
autotypeKey='autotype'

if [ ${WAYLAND_DISPLAY} ]; then
  DOTOOL="wtype"
	if ! type $DOTOOL &>/dev/null; then
    echo "[ERROR] $DOTOOL command not found"
    notify-send "[ERROR] failed to find required '$DOTOOL' command"
    exit 1
	fi
	CLIPSET="wl-copy"
	CLIPGET="wl-paste"
else
  echo "[ERROR] x11 not supported"
  exit 1
fi

# ---------------------- #
#          INFO          #
# ---------------------- #
show-help () {
	echo \
"Usage: pass-menu [OPTIONS] -- COMMAND [ARGS]

Options:
  -p, --path              path to password store
  -c, --clip              copy output to clipboard
      --timeout           timeout for clearing clipboard [default: 45]
  -t, --type              type the output, useful for GUI applications
  -e, --echo              print output to standard output
  -h, --help              display this help and exit
  -v, --version           output version information and exit

Examples:
	pass-menu --clip --timeout 15 -- fzf
	pass-menu --type              -- dmenu -i -l 15"

	exit 0
}

show-version () {
	echo "${VERSION}"
	exit 0
}

error () {
	local  MSG="${1}"; shift 1
	local ARGS="${@}"

	printf "pass-menu: ${MSG}\n" ${ARGS} >&2
	exit 1
}

# ---------------------- #
#          OPTS          #
# ---------------------- #
set-opt-path () {
	local OPTION="${1}"

	if [ ! -d "${OPTION}" ]; then
		error '--path "%s" is not a valid directory.' "${OPTION}"
	fi

	STOREDIR="${OPTION}"
}

set-opt-mode () {
	local OPTION="${1}"

	if [ -n "${MODE}" ] && [ "${MODE}" != "${OPTION}" ]; then
		error 'conflicting option "--%s" with "--%s"' "${OPTION}" "${MODE}"
	fi

	MODE="${OPTION}"
}

set-opt-timeout () {
	local OPTION="${1}"

	if [[ ! "${OPTION}" =~ ^[0-9]+$ ]]; then
		error '"--timeout" must be an integer'
	elif [ "${OPTION}" -lt 10 ]; then
		error '"--timeout" must be greater than 10'
	fi
	
	TIMEOUT="${OPTION}"
}

set-opt-cmd () {
	local OPTION="${*}"

	MENUCMD="${OPTION}"
}

opt-error () {
	local OPTION="${1}"

	error 'invalid option "%s"' "${OPTION}"
}

while [ -v 1 ]; do
	case "${1}" in
		-p | --path)     set-opt-path "${2}"; shift 2 ;;
		-c | --clip)     set-opt-mode 'clip'; shift 1 ;;
		-t | --type)     set-opt-mode 'type'; shift 1 ;;
		-e | --echo)     set-opt-mode 'echo'; shift 1 ;;
		     --timeout)  set-opt-timeout "${2}" ; shift 2 ;;
		-h | --help)     show-help ;;
		-v | --version)  show-version ;;
		--)              shift; set-opt-cmd "${@}"; break ;;
		*)               opt-error "${1}" ;;
	esac
done

if [ -z "${MENUCMD}" ]; then
	error "missing required argument COMMAND"
fi

# ---------------------- #
#         UTILS          #
# ---------------------- #
clip-copy () {
	local VALUE="${1}"
	local ORIG="$(${CLIPGET})"
	local MSG="Copied to clipboard. Will clear in ${TIMEOUT} seconds."
	
	printf "${VALUE}" | ${CLIPSET}
	printf "%s\n" "${MSG}"

	if type notify-send &>/dev/null; then
		notify-send "${MSG}"
	fi

	{
		sleep "${TIMEOUT}" || exit 1
		# restore clipboard back to orginal if it hasn't changed.
		if [ "$(${CLIPGET})" = "${VALUE}" ]; then
			printf "${ORIG}" | ${CLIPSET}
		fi
	} &
}

dotool-type () {
	local VALUE="${1}"
  swaymsg 'focus mode_toggle'
  sleep 0.05
  # FIXME we want to type the value literally, no interpreting of escape chars,
  #  etc. `printf` isn't the right tool for the job, but echo in bash seems to do
  #  the trick. We can also use ${VALUE@Q} or @A if we get stuck, thanks to
  #  https://stackoverflow.com/a/27817504/1410035 for the tip.
  echo -n "${VALUE}" | ${DOTOOL} -
  swaymsg 'focus mode_toggle'
}

# ---------------------- #
#          MAIN          #
# ---------------------- #
get-pass-files () {
	shopt -s nullglob globstar

	local LIST
	LIST=("$STOREDIR"/**/*.gpg)
	LIST=("${LIST[@]#"$STOREDIR"/}")
	LIST=("${LIST[@]%.gpg}")

	printf "%s\n" "${LIST[@]}"
}

get-pass-keys () {
	local PASS_NAME="${1}"
	local PASS_FILE="$(pass "${PASS_NAME}")"
	
	if [ ${#PASS_FILE} -le 1 ]; then
		error '"%s" is too short.' "${PASS_NAME}"
	fi

  if ! echo ${PASS_FILE} | grep -q "$autotypeKey"; then
    echo "$autotypeKey"
  fi

	# Parse Action First
	awk '
	/action(.+)/ {
		match($1, /action\((.+)\)/, a)
		printf "((%s))\n", a[1]
	}' <<< "${PASS_FILE}"

	# Parse Rest of Keys
	awk '
	BEGIN {
		FS=": +"
		password="Yes"
	}

	NR == 1 && ! $2 { print "pass"; password=Null }

	$2 {
		sub("^ +", "", $1)
		if ( $1 == "pass") {
			if (password) {
        print $1
        password=Null
      }
		} else {
			print $1
		}
	}

	/^ *otpauth:/ { print "OTP" }' <<< "${PASS_FILE}"
}

get-pass-value () {
	local PASS_NAME="${1}"
	local PASS_KEY="${2}"

	case "${PASS_KEY}" in
	OTP)
		pass otp "${PASS_NAME}"
	;;
	pass)
		pass "${PASS_NAME}" | awk '
		BEGIN {
			FS=": +"
			password="Yes"
		}

		NR == 1 && ! $2 { print $1; password=Null }

		/pass/ && $2 { if (password) print $2 }'
	;;
	*)
		pass "${PASS_NAME}" | awk -v key="${PASS_KEY}" '
		BEGIN { FS=": +" }

		$2 {
			if ($1 == key)
				for (i=2; i<=NF; i++) print $i
		}'
	;;
	esac
}

get-action () {
	local PASS_NAME="${1}"
	local  ACT_NAME="${2}"

	pass "${PASS_NAME}" | awk -v action="action.+${ACT_NAME}" '{
		if ($1 ~ action)
			for (i=2; i<=NF; i++) print $i
	}'
}

execute-action () {
	local PASS_NAME="${1}"
	shift

	while [ -n "${1}" ]; do
		case "${1}" in
		:clip)
			clip-copy "$(get-pass-value "${PASS_NAME}" "${2}")"
			shift 2
			;;
		:type)
			dotool-type "$(get-pass-value "${PASS_NAME}" "${2}")"
			shift 2
			;;
		:tab)
      dotool-type "$(echo -ne '\t')"
			shift 1
			;;
		:sleep)
			sleep "${2}"
			shift 2
			;;
		:exec | :notify)
			local ACT="${1}"
			local STR="${2:1}"
			shift 2
			# Parse String
			while [ ! "${STR:(-1)}" = '"' ]; do
				if [ -z "${1}" ]; then
					error 'unmatched {"} in %s.' "${PASS_NAME}"
				fi

				STR="${STR} ${1}"
				shift 1
			done

			STR="${STR::(-1)}"

			if [ "${ACT}" = ":exec" ]; then
				sh -c "${STR}"
			else
				notify-send "${STR}"
			fi
			;;
		:*) error "invalid action %s in %s" "${1}" "${PASS_NAME}" ;;
		*)  error "invalid param %s in %s" "${1}" "${PASS_NAME}" ;;
		esac
	done
}

get-mode () {
	if [ -n "${MODE}" ]; then
		printf "${MODE}"
	else
		local CANDIDATES="type\nclip\necho"
		printf "${CANDIDATES}" | PM_PREPOP=off ${MENUCMD}
	fi
}

call-menu () {
	local PIPE="$(< /dev/stdin)"

	[ -z "${PIPE}" ] && exit 1

	printf "${PIPE}" | ${MENUCMD}
}

main () {
	local PASS_NAME PASS_KEY OUT

	PASS_NAME=$(get-pass-files | call-menu)
	[ -z "${PASS_NAME}" ] && exit 1

	PASS_KEY=$(get-pass-keys "${PASS_NAME}" | PM_PREPOP=off call-menu)
	[ -z "${PASS_KEY}" ] && exit 1

  # FIXME need to make "autotype" an inferred action
	if [ "${PASS_KEY:(-2)}" = "))" ]; then
		execute-action "${PASS_NAME}" $(get-action "${PASS_NAME}")
		return 0
  elif [ "${PASS_KEY}" = "$autotypeKey" ]; then
		execute-action "${PASS_NAME}" :type user :tab :type pass
		return 0
	fi

	OUT=$(get-pass-value "${PASS_NAME}" "${PASS_KEY}")

  # FIXME make default "type" and others are key-bindings
	case "$(get-mode)" in
		clip) clip-copy "${OUT}" ;;
		type) dotool-type "${OUT}" ;;
		echo) printf "${OUT}" ;;
	esac
}

main
