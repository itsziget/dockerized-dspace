#!/usr/bin/env bash

REQUIRED_VARIABLES="config.db.password"

CFG_DSPACE=/dspace/config/local.cfg
CFG_LOGPROP=/dspace/config/log4j.properties
CFG_DSC_CROSSWALKS_OAI=/dspace/config/crosswalks/oai/description.xml
CFG_DSC=/dspace/config/description.xml
CFG_ROBOTS="${CATALINA_HOME}/webapps/${APP_NAME}/static/robots.txt"
CFG_ITEM_SUBMISSION="/dspace/config/item-submission.xml"
CFG_FORMS="/dspace/config/input-forms.xml"

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