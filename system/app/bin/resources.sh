#!/usr/bin/env bash

REQUIRED_VARIABLES="config.db.password"

DSPACE_DIR=/app/dspace

CFG_DSPACE="${DSPACE_DIR}/config/local.cfg"
CFG_LOGPROP="${DSPACE_DIR}/config/log4j.properties"
CFG_DSC_CROSSWALKS_OAI="${DSPACE_DIR}/config/crosswalks/oai/description.xml"
CFG_DSC="${DSPACE_DIR}/config/description.xml"
CFG_ROBOTS="${CATALINA_HOME}/webapps/${APP_NAME}/static/robots.txt"
CFG_ITEM_SUBMISSION="${DSPACE_DIR}/config/item-submission.xml"
CFG_FORMS="${DSPACE_DIR}/config/input-forms.xml"
CFG_REST_WEB_XML="${CATALINA_HOME}/webapps/$([[ "${APP_NAME}" == "${APP_ROOT}" ]] && echo "ROOT" || echo "rest")/WEB-INF/web.xml"

toBool () {
    local BOOL=$(echo "${1}" | tr '[:upper:]' '[:lower:]');
    case ${BOOL} in
        1|yes|on|true) echo "true"; ;;
        0|no|off|false) echo "false"; ;;
        *) echo "null";
    esac;
}

getenv() {
    echo "${1}" | awk '{print ENVIRON[$1]}'
}

getenvKeys() {
    awk '
        END {
            for (name in ENVIRON) {
                print name
            }
         }
    ' < /dev/null
}

getConfigKeys() {
    getenvKeys | awk '$0 ~ /^config\./'
}

getConfigMap() {
    getConfigKeys | sort | awk '{key=gensub(/^config\./, "", "g", $1); print key"="ENVIRON[$1]}'
}

checkRequiredEnv() {
    for i in ${REQUIRED_VARIABLES}; do
        if [[ -z "$(getenv "${i}")" ]]; then
            >&2 echo "Variable ${i} is required!";
            return 1;
        fi;
    done;
}

templatize() {
    local SRC=
    for SRC in "${CFG_DSPACE}" \
               "${CFG_LOGPROP}" \
               "${CFG_DSC_CROSSWALKS_OAI}" \
               "${CFG_ROBOTS}" \
               "${CFG_ITEM_SUBMISSION}" \
               "${CFG_FORMS}" \
               "${CFG_REST_WEB_XML}" \
             ; do
        local DST="/app/templates${SRC}.tpl"
        local DST_DIR="$(dirname "${DST}")";
        if [[ -f "${SRC}" ]] && [[ ! -f "${DST}" ]]; then
            mkdir -p "${DST_DIR}"
            mv "${SRC}" "${DST}";
        fi;
    done
}

submissionMapToXml() {
    env | grep '^submission-map\.' \
        | sort \
        | awk '{print gensub(/^submission-map\.([^\.]+)\.([^=]+)=(.*)/, "<name-map submission-name=\"\\3\" collection-handle=\"\\1/\\2\" />", "G")}' \
        | awk '{print gensub(/^submission-map\.default=traditional/, "<name-map submission-name=\"traditional\" collection-handle=\"default\" />", "G")}'
}

formMapToXml() {
    env | grep '^form-map\.' \
        | sort \
        | awk '{print gensub(/^form-map\.([^\.]+)\.([^=]+)=(.*)/, "<name-map form-name=\"\\3\" collection-handle=\"\\1/\\2\" />", "G")}' \
        | awk '{print gensub(/^form-map\.default=traditional/, "<name-map form-name=\"traditional\" collection-handle=\"default\" />", "G")}'
}

renderSubmissionMap() {
    sed -i 's~<name-map.*/>~~' "${CFG_ITEM_SUBMISSION}"
    submissionMapToXml | while read -r line; do sed -i "s~</submission-map>~    ${line}\n</submission-map>~" "${CFG_ITEM_SUBMISSION}"; done;
}

renderFormMap() {
    sed -i 's~<name-map.*/>~~' "${CFG_FORMS}"
    formMapToXml | while read -r line; do sed -i "s~</form-map>~    ${line}\n</form-map>~" "${CFG_FORMS}"; done;
}

renderRobotsTxt() {
    if [[ -f "${CFG_ROBOTS}" ]]; then
        URL="${DS_PROTOCOL}://$(getenv "config.dspace.hostname")${DS_PORT_SUFFIX}"
        sed -i "s~http://localhost:8080/xmlui~${URL}~" "${CFG_ROBOTS}"
    fi;
}

renderOAIDescription() {
    sed -i "s/localhost/$(getenv "config.dspace.hostname")/g" "${CFG_DSC_CROSSWALKS_OAI}"
    sed -i "s/123456789/$(getenv "config.handle.prefix")/g" "${CFG_DSC_CROSSWALKS_OAI}"
}

renderLogConfig() {
    if [[ ! -z "${CFG_LOGPROP}" ]]; then
        sed -i "s/loglevel\.other=INFO/loglevel.other=${DS_LOGLEVEL_OTHER^^}/g" "${CFG_LOGPROP}"
        sed -i "s/loglevel\.dspace=INFO/loglevel.dspace=${DS_LOGLEVEL_DSPACE^^}/g" "${CFG_LOGPROP}"
    fi;
}

removeOverriddenConfigs() {
    for i in "dspace.baseUrl" "solr.server" "db.url"; do
        if [[ -n "$(getenv "config.${i}")" ]]; then
            sed -i 's/^'${i/\./\\.}'\(=\| \).*//g' "${CFG_DSPACE}"
        fi;
    done;
}

renderRestWebXml() {
    if [[ "${APP_NAME}" != "rest" ]] || [[ "$(toBool "${DS_REST_FORCE_SSL}")"  == "true" ]]; then
        return 0
    fi;

    sed -i 's~<transport-guarantee>CONFIDENTIAL</transport-guarantee>~~' "${CFG_REST_WEB_XML}"
}

waitForDatabase() {
    until ${DSPACE_DIR}/bin/dspace database test;
    do
        echo "Waiting for database... [$(date)]";
        sleep 2
    done;
}

exitWithMessage() {
    >&2 echo "${1}" && exit ${2};
}

sedAndSave() {
    sed -i "${1}" "${2}" || exitWithMessage  "sed FAILED: sed -i \"${1}\" \"${2}\"" $?
}

renderLocalConfig() {
    removeOverriddenConfigs

    if [[ "${DS_PORT}" != "" ]]; then
        DS_PORT_SUFFIX=":${DS_PORT}"
    fi;

    for i in DB_HOST DB_PORT DB_SERVICE_NAME PROTOCOL PORT_SUFFIX SOLR_HOSTNAME; do
        local VAR="DS_${i}"
        sedAndSave "s/{{$i}}/${!VAR}/g" "${CFG_DSPACE}"
    done;

    echo "# generated configurations" >> "${CFG_DSPACE}"
    if [[ ! -z "${DS_HIDDEN_METADATA}" ]]; then
        IFS=$', \n\r'
        for i in ${DS_HIDDEN_METADATA}; do
            echo "metadata.hide.${i} = true" >> "${CFG_DSPACE}"
        done;
    fi;

    if [[ ! -z "${DS_CUSTOM_CONFIG}" ]]; then
        IFS=$'\n\r'
        for i in ${DS_CUSTOM_CONFIG}; do
            echo "${i}" >> "${CFG_DSPACE}"
        done;
    fi;

    getConfigMap >> "${CFG_DSPACE}"
}

renderTemplates() {

    local file=""
    for file in $(find /app/templates -type f -name *.tpl); do
        cp "${file}" "${file:14:-4}"
    done;

    renderLocalConfig
    renderLogConfig
    renderOAIDescription
    renderRobotsTxt
    renderSubmissionMap
    renderFormMap
    renderRestWebXml
}

prepareDSpaceApp() {
    checkRequiredEnv || exit $?

    renderTemplates
    waitForDatabase
}