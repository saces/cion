#!/bin/bash

set -e
shopt -s nullglob

# Usage info
show_help() {
cat << EOFHELP
Usage: ${0##*/} [global options] command [command options] [argument]...
Commands
        help
        version
        register [-w] zonename
        update zonename oldAddr newAddr
        updateA zonename name ip4
        updateAAAA zonename name ip6
        updateMX zonename name dest [pref]
        updateCNAME zonename name dest
        updateTXT zonename key value
        updateSRV zonename name proto prio weight port host
        deletezone zonename
Global options
        -d path
            directory for storing tokens & items
        -s url
            server server url
        -u user
            use this users home dir
EOFHELP
if [[ -n "${1}" ]]; then exit ${1}; fi
exit 0
}

show_version() {
cat << EOFVERSION
${0##*/} version 0.0.1
EOFVERSION
exit 0
}

# store a token
# store_token name token
store_token() {
    # XCION_ZONE_TOKENS_PATH
    # ensure path exists
    if [[ ! -e ${XCION_ZONE_TOKENS_PATH} ]]; then
        mkdir -p ${XCION_ZONE_TOKENS_PATH}
        echo "DEBUG: Created dir: '${XCION_ZONE_TOKENS_PATH}'"
    elif [[ ! -d $XCION_ZONE_TOKENS_PATH ]]; then
        echo "Error: '${XCION_ZONE_TOKENS_PATH}' already exists but is not a directory"
        exit -1
    fi
    fname="${XCION_ZONE_TOKENS_PATH}/${1}"
    echo "${2}" > ${fname}
}

# read a token
# read_token zonename
# afterwards XCION_ZONE_TOKEN is set
read_token() {
    unset XCION_ZONE_TOKEN
    #value=$(<config.txt)
    XCION_ZONE_TOKEN=$(<${XCION_ZONE_TOKENS_PATH}/${1})
}

# register a domain
register_namespace() {
# store the whole response with the status at the and
HTTP_RESPONSE=$(curl -s \
    -w '\n%{http_code}' \
    -X PUT \
    -H "Accept: application/json; version=1.0.0" \
    -H "Content-Type: application/json" \
    -d "{\"zone\": \"${1}\"}" \
    ${CION_WEB_URL}/register)

# extract the body
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed \$d)

# extract the status
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n 1)

# print the body
#echo "BODY: $HTTP_BODY"
#echo "STATUS: *$HTTP_STATUS*"

# example using the status
case "$HTTP_STATUS" in
    202)    #echo "Domain created. Access token:"
            TOKEN=$(echo "$HTTP_BODY" | sed -e 's/[":,{}]//g' -e 's/\([a-z ]*\)auth_key//')
            store_token ${1} ${TOKEN}
            exit 0
            ;;
    423)    echo "Domain already taken."
            exit 11
            ;;
    429)    TIME=$(echo "$HTTP_BODY" | sed -e 's/[":{}]//g' -e 's/\([a-z ]*\)\([0-9]\{1,2\}h[0-9]\{1,2\}m[0-9]\{1,2\}s\)/\2/' -e 's/[mh]/:/g' -e 's/s//')
            
            
            echo "Time to wait for next registration: ${TIME}"

            if [[ -n ${2} ]]; then
                sleep $(TZ="UTC" date -d "1970-01-01 ${TIME}" +%s)
                register_namespace ${1} 1
            fi

            exit 12
            ;;
    *)  echo "wut? $HTTP_STATUS"
        exit 13
        ;;
esac
}


# updateA zone item ip
updateA() {
    read_token ${1}
    # XCION_ZONE_TOKEN

# store the whole response with the status at the and
HTTP_RESPONSE=$(curl -s \
    -w '\n%{http_code}' \
    -X POST \
    -H "Accept: application/json; version=1.0.0" \
    -H "Content-Type: application/json" \
    -H "X-Cion-Auth-Key: ${XCION_ZONE_TOKEN}" \
    -H "X-Cion-Update-Type: A" \
    -d "{\"name\": \"${2}\", \"address\": \"${3}\"}" \
    ${CION_WEB_URL}/zone/${1})

# extract the body
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed \$d)

# extract the status
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n 1)

# print the body
echo "BODY: ${HTTP_BODY}"
echo "STATUS: *${HTTP_STATUS}*"

# example using the status
case "$HTTP_STATUS" in
    202)    echo "Domain updated"
            #TOKEN=$(echo "$HTTP_BODY" | sed -e 's/[":,{}]//g' -e 's/\([a-z ]*\)auth_key//')
            #store_token ${1} ${TOKEN}
            exit 0
            ;;
    *)  echo "wut? $HTTP_STATUS"
        exit 13
        ;;
esac
}

##################################
# Commandline processing
##################################

# begin
if [[ $# -eq 0 ]]; then
    echo "ERROR: no arguments given."
    show_help 1
fi

# global options
while getopts ":d:s:u:h" opt; do
    case $opt in
        h)  show_help
            ;;
        d)  if [[ -n "${XCION_DATA_USER}" ]]; then
                echo "Error: The -d and -u option are mutually exclusive."
                show_help 3
            fi
            XCION_ZONE_TOKENS_PATH="${OPTARG}"
            ;;
        s)  CION_WEB_URL="${OPTARG}"
            ;;
        u)  if [[ -n "${XCION_ZONE_TOKENS_PATH}" ]]; then
                echo "Error: The -u and -d option are mutually exclusive."
                show_help 4
            fi
            homedir=$( getent passwd "${OPTARG}" | cut -d: -f6 )
            if [[ -z "${homedir}" ]]; then
                echo "Error: Could not get the homedir for user '${OPTARG}'."
                exit 5
            fi
            XCION_DATA_USER="${OPTARG}"
            XCION_ZONE_TOKENS_PATH="${homedir}/.xcion/zones"
            ;;
        -)
            ;;
        \?)
            echo "[ERROR] Invalid option: -${OPTARG}"
            show_help 3
            ;;
    esac
done
shift $((OPTIND-1))

# config
# TPL_* values are sed'ed by the docker script with
# the defaults to fit your configuration
CION_WEB_URL="${CION_WEB_URL:-TPL_CION_WEB_URL}"
#CION_WEB_URL="${CION_WEB_URL:-http://127.0.0.1:1234}"

# where to read/store the zone keys?
# TODO consider /etc or /var/lib for root/global

if [[ $EUID -ne 0 ]]; then
  XCION_ZONE_TOKENS_PATH=${XCION_ZONE_TOKENS_PATH:-~/.xcion/zones}
else
  XCION_ZONE_TOKENS_PATH=${XCION_ZONE_TOKENS_PATH:-/var/lib/xcion/zones}
fi

#if [[ ! -d "${XCION_ZONE_TOKENS_PATH}" ]]; then
#    echo "Error: Zone path '${XCION_ZONE_TOKENS_PATH}' does not exist or is not a directory"
#    exit 4
#fi

echo "DEBUG: Zone path '${XCION_ZONE_TOKENS_PATH}'"


# get the command
CMD=${1}
shift

case ${CMD} in
    help | --help )
        show_help
        ;;
    version | --version )
        show_version
        ;;
    register )
        while getopts ":w" opt; do
            case $opt in
                w)
                    OPT_REGWAIT=1
                    shift $((OPTIND-1))
                    ;;
                \?)
                    echo "[ERROR] Invalid option: -${OPTARG}"
                    show_help 4
                    ;;
            esac
        done
        if [[ $# -gt 1 ]]; then
            echo "[ERROR] Extra arguments given."
            show_help 5
        fi
        if [[ $# -eq 0 ]]; then
            echo "[ERROR] No domain name given."
            show_help 6
        fi
        register_namespace ${1} ${OPT_REGWAIT}
        ;;
    updateA )
        if [[ $# -ne 3 ]]; then
            echo "[ERROR] Wrong argument count."
            show_help 7
        fi
        updateA $1 $2 $3
        ;;

    # TODO
    #   update zonename oldAddr newAddr
    #   updateA zonename name ip4
    #   updateAAAA zonename name ip6
    #   updateMX zonename name dest [pref]
    #   updateCNAME zonename name dest
    #   updateTXT zonename key value
    #   updateSRV zonename name proto prio weight port host
    #   deletezone zonename

    update|updateAAAA|updateMX|updateCNAME|updateTXT|updateSRV|deletezone)
        echo -e "TODO: Commnd '${CMD}' not implemented yet.\nDear coding being, would you be so kind and send a patch?"
        exit -1
        ;;

    *)  echo "ERROR: Unrecognized commnd '${CMD}'"
        show_help 2
        ;;
esac

exit 255
