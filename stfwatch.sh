#!/usr/bin/env bash

# run this script on each peer to troubleshoot sync issues
# https://github.com/syncthing/syncthing/issues/9371
# requires `jq`

#sequence nums are a vector clock - https://en.wikipedia.org/wiki/Vector_clock
_enum() {
	find . \
	-type f \
	-name "*.json" \
	-exec jq -r '"\(input_filename|split("/")[-1]) \t global:\(.global.sequence|tostring) \t local:\(.local.sequence|tostring)"' {} \; |
	sort -n
}

_listFolders() {
	for f in "${!VALID_FIDS[@]}"; do
		printf '%s  %s\n' "$f" "[${VALID_FIDS[$f]}]"
	done
}

#path to syncthing binary
ST_BIN='/Applications/Syncthing.app/Contents/Resources/syncthing/syncthing'

#if not on macOS, you must set manually
ST_APIKEY=$(defaults read com.github.xor-gate.syncthing-macosx ApiKey)

#if not running on macOS, use the hardcoded value
ST_URI=$(defaults read com.github.xor-gate.syncthing-macosx URI)
#ST_URI=http://127.0.0.1:8384
[[ -n $ST_URI ]] || { echo 1>&2 "error: syncthing API endpoint not declared"; return 1; }
ST_API="$ST_URI/rest"

FOLDERS_RAW=$(curl \
	--location \
	--silent \
	--header "X-API-Key: $ST_APIKEY" \
	"$ST_API/config/folders" |
	jq 2>/dev/null -r '.[] // empty | "[\(.id)]=\(.label)"')
if [[ -n $FOLDERS_RAW ]]; then
	eval "declare -A VALID_FIDS=($FOLDERS_RAW)"
fi

#device ID (short)
IFS='-' read -r MYID _ < <(curl -sIo /dev/null "$ST_API/noauth/health" -w '%header{X-Syncthing-Id}')

case $1 in
	-h|--help) echo "usage: ${0##*/} -f <folderID> <relative_path>"; exit;;
	-e|--enum) _enum; exit;;
	-f) FID=$2; shift 2;;
	'') echo "supply a pathname (relative to the top level of your sync folder)"; exit 1;;
esac

if [[ -z $FID ]] || [[ -z ${VALID_FIDS[$FID]} ]]; then
	echo "supply a valid folderID with \`-f <folderID>\`:"
	_listFolders
	exit 1
fi

while true ; do

#https://docs.syncthing.net/rest/debug.html#get-rest-debug-file
#https://docs.syncthing.net/rest/db-file-get.html
RES=$($ST_BIN cli debug file "$FID" "$1" 2>/dev/null)
sleep 0.5
[[ $RES == "$LASTRES" ]] && continue
FNAME="${EPOCHREALTIME}_${1##*/}_${MYID}-${HOSTNAME}.json"
echo "$RES" >"$FNAME"
echo "$(date) wrote change to $FNAME"
LASTRES="$RES"

done
