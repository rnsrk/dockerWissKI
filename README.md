# Docker WissKI

## Prerequisites

### Get the data
Clone the repository. In case of problems with large files just download the zip.

### Linux
Install [Docker](https://docs.docker.com/get-docker/). You may want to apply some [post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/). 

### Windows
Install [Docker Desktop](https://docs.docker.com/get-docker/). You may need to install the [WSL 2 Linux kernel](https://docs.microsoft.com/de-de/windows/wsl/install-win10).  

**Beware if you are using Virtualization software like VirtualBox, they may conflict with your Docker-Software in Windows.**

You need a GraphDB standalone server zip file. Apply on the [GraphDB free downloadpage](https://www.ontotext.com/products/graphdb/graphdb-free/), they will send you an email with a link to the stand alone server; safe the file as `graphdb.zip` in the `graphdb_context` folder. 

## Setup
### Script-driven (only Linux)
Run `./setup.bash` to set your database credentials and port definitions.
### Windows and without script
Open `.example-env` file, provide the credentials and ports according to your needs and save it as `.env`.
Open `drupal-context/example-settings.php` and paste the credentials there, too and safe it as `drupal-context/settings.php` Go to the DATABASE SECTION at line 775 and change:
~~~php
  'database' => 'DBNAME',
  'username' => 'DBUSER',
  'password' => 'USERPW',
  'port' => 'DBPORT',
 ~~~
## Start
Run `docker compose up -d` to start containers in background.

## Logs
You can check the logs of each container by typing `docker logs <container-name>`, i.e. `docker logs dockerwisski_drupal_1`.

## Docker compose environment

### Services
There are four services corresponding to four containers
- drupal/ dockerwisski_drupal_1
- graphdb/ dockerwisski_graphdb_1
- mariadb/ dockerwisski_mariadb_1
- phpmyadmin/ dockerwisski_phpmyadmin_1
- solr/ dockerwisski_solr_1

To browse your services enter your domain and the port of the service (i.e. `localhost:7200` if you installed it on your local machine and left the default graphdb port).

To connect to your services over the internal docker network, you have to provide the service name (drupal, mariadb, solr, graphdb) as host instead of `localhost` or `172.168.0.1`. For example the correct setting in the settings.php for host is not  `'host' => 'localhost'`, but  `'host' => 'mariadb'`. 

### Editing
If you want to jump into a container, open a console and type
~~~bash
docker exec -it <container-id> bash
~~~
for example 
~~~bash
docker exec -it dockerwisski_drupal_1 bash
~~~
gets you into the drupal container.

### Volumes
All containers have three bind volumes:
- drupal-data stores your drupal root directory
- mariadb-data corresponds to /var/lib/mysql
- solr-data to SORL root dir

and one docker managed volume:
- graphdb-data to Graphdb /graphdb

You find these bind volumes in your git directory and the docker managed under `/var/lib/docker/volumes/<composer-prefix>_<volume name>/_data` (Linux - you have to be root to access) or at the location shown in your Docker Desktop settings (Premium Feature). Please check the right permissions, if you copy or alter files and folders.

