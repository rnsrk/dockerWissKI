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
echo -e "${GREEN}Please provide the credentials for the MariaDB, we store them in .env to create the user and database via docker and ${NC}"
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
    while [[ -z $ROOTPW ]]
    do
        read ROOTPW
        if [[ -z $ROOTPW ]]
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
    echo -e "${GREEN}Root password: ${ROOTPW}${NC}"
    echo -e "${GREEN}Database user name: ${DBUSER}${NC}"
    echo -e "${GREEN}Database user password: ${USERPW}${NC}"
    echo -e "${YELLOW}Is that correct? (Y/n)"
    read SURE
    if [[ $SURE == 'y' ]] || [[ $SURE == 'Y' ]] || [[ -z $SURE ]]
    then 
        export DBNAME
        export ROOTPW
        export DBUSER
        export USERPW
        FINISHED=true
    else
        unset DBNAME
        unset ROOTPW
        unset DBUSER
        unset USERPW
        echo -e "${GREEN}Okay then...${NC}"
    fi
done
unset FINISHED

printf "\n"
echo -e "${GREEN}Writing credentials to .env. ${NC}"

echo "MARIADB_ROOT_PASSWORD=${ROOTPW}
MARIADB_USER=${DBUSER}
MARIADB_PASSWORD=${USERPW}
MARIADB_DATABASE=${DBNAME}" > .env

printf "\n"

echo -e "${GREEN}Lets define the ports for your services. Be sure that they are not busy!${NC}"
printf "\n"

FINISHED=false
re='^[0-9]+$'
while [ $FINISHED == false ]
do
    echo -e "${YELLOW}What should be the port of Drupal (default 80)?${NC}"
    while [[ -z $DRUPALPORT ]]
    do
        read DRUPALPORT
        if [[ -z $DRUPALPORT ]]
        then
            DRUPALPORT=80
            echo -e "${GREEN}Take default port ${DRUPALPORT}.${NC}"
        fi
        if ! [[ $DRUPALPORT =~ $re ]] ; then
            echo -e "${RED}Drupal port has to be a integer!${NC}"
        fi
    done

    echo -e "${YELLOW}What should be the port of MariaDB (default 3306)?${NC}"
    while [[ -z $MARIADBPORT ]]
    do
        read MARIADBPORT
        if [[ -z $MARIADBPORT ]]
        then
            MARIADBPORT=3306
            echo -e "${GREEN}Take default port ${MARIADBPORT}.${NC}"
        fi
        if ! [[ $MARIADBPORT =~ $re ]] ; then
            echo -e "${RED}MariaDB port has to be a integer, like 3306.${NC}"
        fi
    done

    echo -e "${YELLOW}What should be the port of Graphdb (default 7200)?${NC}"
    while [[ -z $GRAPHDBPORT ]]
    do
        read GRAPHDBPORT
        if [[ -z $GRAPHDBPORT ]]
        then
            GRAPHDBPORT=7200
            echo -e "${GREEN}Take default port ${GRAPHDBPORT}.${NC}"
        fi
        if ! [[ $GRAPHDBPORT =~ $re ]] ; then
            echo -e "${RED}GraphDB port has to be a integer, like 7200.${NC}"
        fi
    done

    echo -e "${YELLOW}Which port should be used for Solr (default 8983)?${NC}"
    while [[ -z $SOLRPORT ]]
    do
        read SOLRPORT
        if [[ -z $SOLRPORT ]]
        then
            SOLRPORT=8983
            echo -e "${GREEN}Take default port ${SOLRPORT}.${NC}"
        fi
        if ! [[ $SOLRPORT =~ $re ]] ; then
            echo -e "${RED}Solr port has to be a integer, like 8983.${NC}"
        fi
    done

    echo -e "${YELLOW}What should be the port of PHPmyAdmin (default 8081)?${NC}"
    while [[ -z $PHPMYADMINPORT ]]
    do
        read PHPMYADMINPORT
        if [[ -z $PHPMYADMINPORT ]]
        then
            PHPMYADMINPORT=8081
            echo -e "${GREEN}Take default port ${PHPMYADMINPORT}.${NC}"
        fi
        if ! [[ $PHPMYADMINPORT =~ $re ]] ; then
            echo -e "${RED}Drupal port has to be a integer!${NC}"
        fi
    done
    printf "\n"
    echo -e "${GREEN}Drupal port: ${DRUPALPORT}${NC}"   
    echo -e "${GREEN}MariaDB port: ${MARIADBPORT}${NC}"
    echo -e "${GREEN}GraphDB port: ${GRAPHDBPORT}${NC}"
    echo -e "${GREEN}Solr port: ${SOLRPORT}${NC}"
    echo -e "${GREEN}PHPmyAdmin port: ${PHPMYADMINPORT}${NC}"
    echo -e "${YELLOW}Is that correct? (Y/n)"
    read SURE
    if [[ $SURE == 'y' ]] || [[ $SURE == 'Y' ]] || [[ -z $SURE ]]
    then 
        export DRUPALPORT
        export MARIADBPORT
        export GRAPHDBPORT
        export SOLRPORT
        export PHPMYADMINPORT
        FINISHED=true
    else
        unset DRUPALPORT
        unset MARIADBPORT
        unset GRAPHDBPORT
        unset SOLRPORT
        export PHPMYADMINPORT
        echo -e "${GREEN}Okay then...${NC}"
    fi
done
unset FINISHED

echo -e "${GREEN}Add ports to .env ${NC}"
echo "DRUPAL_PORT=${DRUPALPORT}
MARIADB_PORT=${MARIADBPORT}
GRAPHDB_PORT=${GRAPHDBPORT}
SOLR_PORT=${SOLRPORT}
PHPMYADMIN_PORT=${PHPMYADMINPORT}
" >> .env

printf "\n"
echo -e "${GREEN}create and save credentials in settings.php. ${NC}"
cp ./drupal_context/example-settings.php ./drupal_context/settings.php
sed -i "s/'database' =>.*/'database' => '${DBNAME}',/" ./drupal_context/settings.php 
sed -i "s/'username' =>.*/'username' => '${DBUSER}',/" ./drupal_context/settings.php 
sed -i "s/'password' =>.*/'password' => '${USERPW}',/" ./drupal_context/settings.php
sed -i "s/'port' =>.*/'port' => '3306',/" ./drupal_context/settings.php


printf "\n"
echo -e "${GREEN}Type docker-compose up -d to start the containers in the background${NC}"
echo -e "${GREEN}then visit http://localhost:${DRUPALPORT} to start the Drupal installer.${NC}"
