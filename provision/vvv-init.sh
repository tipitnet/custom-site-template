#!/usr/bin/env bash
# Provision WordPress Stable

DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`

echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
mysql -u root --password=root ${DB_NAME} < /srv/database/backups/${DB_NAME}.sql

echo -e "\nReplacing production data into db tables, if set."
cat ${VVV_CONFIG} | shyaml get-values-0 sites.${SITE_ESCAPED}.replace_strings  2> /dev/null|
    while IFS='' read -r -d '' key &&
          IFS='' read -r -d '' value; do
              echo "'$key' -> '$value'"
              noroot wp search-replace ${key} ${value} --skip-columns=guid --skip-packages --skip-themes --skip-plugins --path=${VVV_PATH_TO_SITE}
    done

echo -e "\nCopying media, if set."
cat ${VVV_CONFIG} | shyaml get-values-0 sites.${SITE_ESCAPED}.media_folders  2> /dev/null|
    while IFS='' read -r -d '' key &&
          IFS='' read -r -d '' value; do
              echo "'$key' -> '${VVV_PATH_TO_SITE}/$value'"
              [ -d "${VVV_PATH_TO_SITE}/$value" ] || noroot mkdir "${VVV_PATH_TO_SITE}/$value"
		      noroot cp -r "$key/."  "${VVV_PATH_TO_SITE}/$value"
    done
	
echo -e "\nSetting NGINX logs."
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

echo -e "\nSetting NGINX custom site file."
cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

echo -e "\nSetting hosts file."
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-hosts"
