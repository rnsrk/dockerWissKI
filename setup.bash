#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# introduction
echo -e "${GREEN}Hi, this script prepares the Docker-WissKI setup for you!${NC}"
sleep 3
printf "\n"

# check if graphdb.zip is on place
echo -e "${GREEN}Lets see, if graphdb.zip is in ./graphdb_context ...${NC}"

FILE=./graphdb_context/graphdb.zip

if [[ -f "$FILE" ]]
then
    echo -e "${GREEN}Yes, we can proceed.${NC}"
else
	echo -e "${RED}No, please visit https://www.ontotext.com/products/graphdb/graphdb-free/ and apply for the recent version."
	echo -e "Save as \"graphdb.zip\" in folder \"graphdb_context\".${NC}"
fi

# ask for credentials
printf "\n"
echo -e "${GREEN}Please provide the credentials for the Database, we store them in .env to create the user and database via docker and ${NC}"
echo -e "${GREEN}save them in settings.php for Drupal to establish the database connection. ${NC}"
printf "\n"

FINISHED=false
while [ $FINISHED == false ]
do
    echo -e "${YELLOW}What should be the name of the database?${NC}"
    while [[ -z $DBNAME ]]
    do
        read DBNAME
        if [[ -z $DBNAME ]]
        then
            echo -e "${RED}Database name can not be emtpy! Please enter a database name!${NC}"
        fi
    done
    echo -e "${YELLOW}What should be the password of the database root?${NC}"
    while [[ -z $DB_ROOT_PASSWORD ]]
    do
        read DB_ROOT_PASSWORD
        if [[ -z $DB_ROOT_PASSWORD ]]
        then
            echo -e "${RED}Database root password can not be emtpy! Please enter a password!${NC}"
        fi
    done
    echo -e "${YELLOW}Enter your database user name:${NC}"
    while [[ -z $DBUSER ]]
    do
        read DBUSER
        if [[ -z $DBUSER ]]
        then
            echo -e "${RED}Database user name can not be emtpy! Please enter database user name!${NC}"
        fi
    done
    echo -e "${YELLOW}Enter your database user password:${NC}"
    while [[ -z $USERPW ]]
    do
        read USERPW
        if [[ -z $USERPW ]]
        then
            echo -e "${RED}Database user password can not be emtpy! Please enter database user name!${NC}"
        fi
    done
    printf "\n"
    echo -e "${GREEN}Database name: ${DBNAME}${NC}"
    echo -e "${GREEN}Root password: ${DB_ROOT_PASSWORD}${NC}"
    echo -e "${GREEN}Database user name: ${DBUSER}${NC}"
    echo -e "${GREEN}Database user password: ${USERPW}${NC}"
    echo -e "${YELLOW}Is that correct? (Y/n)"
    read SURE
    if [[ $SURE == 'y' ]] || [[ $SURE == 'Y' ]] || [[ -z $SURE ]]
    then
        export DBNAME
        export DB_ROOT_PASSWORD
        export DBUSER
        export USERPW
        FINISHED=true
    else
        unset DBNAME
        unset DB_ROOT_PASSWORD
        unset DBUSER
        unset USERPW
        echo -e "${GREEN}Okay then...${NC}"
    fi
done
unset FINISHED

printf "\n"
echo -e "${GREEN}Writing credentials to .env. ${NC}"

echo "DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_USER=${DBUSER}
DB_PASSWORD=${USERPW}
DB_DATABASE=${DBNAME}" > .env

printf "\n"

echo -e "${GREEN}Lets define the ports for your services. Be sure that they are not busy!${NC}"
printf "\n"

FINISHED=false
re='^[0-9]+$'
while [ $FINISHED == false ]
do
    echo -e "${YELLOW}What should be the port of Drupal (default 80)?${NC}"
    while [[ -z $DRUPAL_PORT ]]
    do
        read DRUPAL_PORT
        if [[ -z $DRUPAL_PORT ]]
        then
            DRUPAL_PORT=80
            echo -e "${GREEN}Take default port ${DRUPAL_PORT}.${NC}"
        fi
        if ! [[ $DRUPAL_PORT =~ $re ]] ; then
            echo -e "${RED}Drupal port has to be a integer!${NC}"
        fi
    done

    echo -e "${YELLOW}What should be the port of Database (default 3306)?${NC}"
    while [[ -z $DB_PORT ]]
    do
        read DB_PORT
        if [[ -z $DB_PORT ]]
        then
            DB_PORT=3306
            echo -e "${GREEN}Take default port ${DB_PORT}.${NC}"
        fi
        if ! [[ $DB_PORT =~ $re ]] ; then
            echo -e "${RED}Database port has to be a integer, like 3306.${NC}"
        fi
    done

    echo -e "${YELLOW}What should be the port of Graphdb (default 7200)?${NC}"
    while [[ -z $GRAPHDB_PORT ]]
    do
        read GRAPHDB_PORT
        if [[ -z $GRAPHDB_PORT ]]
        then
            GRAPHDB_PORT=7200
            echo -e "${GREEN}Take default port ${GRAPHDB_PORT}.${NC}"
        fi
        if ! [[ $GRAPHDB_PORT =~ $re ]] ; then
            echo -e "${RED}GraphDB port has to be a integer, like 7200.${NC}"
        fi
    done

    echo -e "${YELLOW}Which port should be used for Solr (default 8983)?${NC}"
    while [[ -z $SOLR_PORT ]]
    do
        read SOLR_PORT
        if [[ -z $SOLR_PORT ]]
        then
            SOLR_PORT=8983
            echo -e "${GREEN}Take default port ${SOLR_PORT}.${NC}"
        fi
        if ! [[ $SOLR_PORT =~ $re ]] ; then
            echo -e "${RED}Solr port has to be a integer, like 8983.${NC}"
        fi
    done

    echo -e "${YELLOW}What should be the port of PHPmyAdmin (default 8081)?${NC}"
    while [[ -z $DB_ADMINISTRATION_PORT ]]
    do
        read DB_ADMINISTRATION_PORT
        if [[ -z $DB_ADMINISTRATION_PORT ]]
        then
            DB_ADMINISTRATION_PORT=8081
            echo -e "${GREEN}Take default port ${DB_ADMINISTRATION_PORT}.${NC}"
        fi
        if ! [[ $DB_ADMINISTRATION_PORT =~ $re ]] ; then
            echo -e "${RED}Drupal port has to be a integer!${NC}"
        fi
    done
    printf "\n"
    echo -e "${GREEN}Drupal port: ${DRUPAL_PORT}${NC}"
    echo -e "${GREEN}Database port: ${DB_PORT}${NC}"
    echo -e "${GREEN}GraphDB port: ${GRAPHDB_PORT}${NC}"
    echo -e "${GREEN}Solr port: ${SOLR_PORT}${NC}"
    echo -e "${GREEN}PHPmyAdmin port: ${DB_ADMINISTRATION_PORT}${NC}"
    echo -e "${YELLOW}Is that correct? (Y/n)"
    read SURE
    if [[ $SURE == 'y' ]] || [[ $SURE == 'Y' ]] || [[ -z $SURE ]]
    then
        export DRUPAL_PORT
        export DB_PORT
        export GRAPHDB_PORT
        export SOLR_PORT
        export DB_ADMINISTRATION_PORT
        FINISHED=true
    else
        unset DRUPAL_PORT
        unset DB_PORT
        unset GRAPHDB_PORT
        unset SOLR_PORT
        export DB_ADMINISTRATION_PORT
        echo -e "${GREEN}Okay then...${NC}"
    fi
done
unset FINISHED

echo -e "${GREEN}Add ports to .env ${NC}"
echo "DB_ADMINISTRATION_PORT=${DB_ADMINISTRATION_PORT}
DB_DRIVER=mysql
DB_HOST=mariadb
DB_NAME=${DBNAME}
DB_PASSWORD=USERPW
DB_PORT=${DB_PORT}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_USER=${DB_USER}
DRUPAL_PORT=${DRUPAL_PORT}
GRAPHDB_PORT=${GRAPHDB_PORT}
SOLR_PORT=${SOLR_PORT}

" >> .env


printf "\n"
echo -e "${GREEN}Type docker compose up -d to start the containers in the background${NC}"
echo -e "${GREEN}then visit http://localhost:${DRUPAL_PORT} to start the Drupal installer.${NC}"
