#!/usr/bin/env bash
# Provision WordPress Stable
DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
REPO_DOMAIN=`get_config_value 'repo_domain' ''`
REPO_KEY=`get_config_value 'repo_key' ''`
REPO_CONTENT=`get_config_value 'repo_content' ''`
DB_NAME=`get_config_value 'db_name' ''`
VVV_PATH_TO_WP_SITE=${VVV_PATH_TO_SITE}/public_html
PRODUCTION_DOMAIN=`get_config_value 'production_domain' ''`

echo -e "\nSetting private key to access repo."
noroot cp /srv/config/certs-config/${REPO_KEY} /home/vagrant/.ssh/id_rsa
noroot chmod 600 /home/vagrant/.ssh/id_rsa

echo -e "\nSetting WP core."
noroot wp core download --path="${VM_DIR}/public_html" --allow-root
echo -e "\nCreating WP config file."
noroot wp config create --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --path="${VM_DIR}/public_html" --extra-php <<PHP
define( 'WP_DEBUG', false );
PHP

echo -e "\nIncluding repo into known hosts."
if [[ ! "$REPO_DOMAIN" == '' ]]; then
	noroot ssh-keyscan -t rsa "$REPO_DOMAIN" >> /etc/ssh/ssh_known_hosts
fi

echo -e "\nGetting code from repo."	
cd ${VM_DIR}/public_html
noroot git init
noroot git remote add origin ${REPO_CONTENT}
noroot git fetch
noroot git reset --hard origin/master  


echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
mysql -u root --password=root ${DB_NAME} < /srv/database/backups/${DB_NAME}.sql


cd ${VM_DIR}
echo -e "\nReplacing production data into db tables, if set."
cat ${VVV_CONFIG} | shyaml get-values-0 sites.${SITE_ESCAPED}.custom.replace_strings  2> /dev/null|
    while IFS='' read -r -d '' key &&
          IFS='' read -r -d '' value; do
              echo "'$key' -> '$value'"
              noroot wp search-replace ${key} ${value} --skip-columns=guid --skip-packages --skip-themes --skip-plugins --path=${VVV_PATH_TO_WP_SITE}
    done

echo -e "\nCopying media, if set."
cat ${VVV_CONFIG} | shyaml get-values-0 sites.${SITE_ESCAPED}.custom.media_folders  2> /dev/null|
    while IFS='' read -r -d '' key &&
          IFS='' read -r -d '' value; do
              echo "'$key' -> '${VVV_PATH_TO_WP_SITE}/$value'"
              [ -d "${VVV_PATH_TO_WP_SITE}/$value" ] || noroot mkdir "${VVV_PATH_TO_WP_SITE}/$value"
		      noroot cp -r "$key/."  "${VVV_PATH_TO_WP_SITE}/$value"
    done
	
echo -e "\nSetting NGINX logs."
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

echo -e "\nSetting NGINX custom site file."
cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{PRODUCTION_DOMAIN_HERE}}#${PRODUCTION_DOMAIN}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

echo -e "\nSetting hosts file."
cp -f "${VVV_PATH_TO_SITE}/provision/vvv-hosts.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-hosts"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-hosts"
