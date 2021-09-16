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
printf "\n"
echo -e "${GREEN}Writing credentials to .env. ${NC}"

echo "MYSQL_ROOT_PASSWORD=${ROOTPW}
MYSQL_USER=${DBUSER}
MYSQL_PASSWORD=${USERPW}
MYSQL_DATABASE=${DBNAME}" > .env

echo -e "${GREEN}and replace credentials in settings.php. ${NC}"
sed -i "s/'database' =>.*/'database' => '${DBNAME}'/" ./drupal_context/settings.php 
sed -i "s/'username' =>.*/'username' => '${DBUSER}'/" ./drupal_context/settings.php 
sed -i "s/'password' =>.*/'password' => '${USERPW}'/" ./drupal_context/settings.php 