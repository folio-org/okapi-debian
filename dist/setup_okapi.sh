#!/bin/bash

# setup_okapi.sh
# Config creation script for folio-okapi


# ================================= Copyright =================================
# Version 0.1.5 (2020-07-21), Copyright (C) 2020
# Author: Jo Drexl (johannes.drexl@lrz.de) for FOLIO
# Coauthors: -

#   This file is part of the LRZ FOLIO debian package

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#    http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#   On Debian systems, the full text of the Apache License version 2.0
#   can be found in the file 
#     `/usr/share/common-licenses/Apache-2.0'


# ================================= Variables =================================

# Config example file (absolute path)
FO_EXAMPLE="/usr/share/doc/folio/okapi/okapi.conf.debian"

# Final config file (absolute path)
FO_CONFIG="/etc/folio/okapi/okapi.conf"

# Temp file (contains passwords, thus resides in RAM only)
FO_TEMP="/dev/shm/setup_okapi.tmp"


# ================================= Functions =================================

# Exit on cancel
fo_cancel() {
  export NEWT_COLORS='root=,red'
  whiptail --title "Okapi - Abort" --msgbox \
    "Abort by user. Please copy example config from '$FO_EXAMPLE' to '$FO_CONFIG' and modify it manually." 8 78
  exit 0
}

# Exit on cancel during PostgreSQL setup
fo_pgcancel() {
  export NEWT_COLORS='root=,red'
  whiptail --title "Okapi - Abort" --msgbox \
    "Abort by user. Please setup your postgres server manually." 8 78
  exit 0
}


# =============================== Prerequisites ===============================

# Check if being root
if [ "$(whoami)" != "root" ]
  then
    echo -e "\nThis script has to be invocated by root. Aborting!"
    exit 0
fi

# Check if there's already a config
if [ -f "$FO_CONFIG" ]
  then
    if ! whiptail --title "Okapi - Config" --defaultno \
      --yesno "Overwrite existing config with new settings?" 8 78
      then
        echo -e "\nConfig found, skipping setup."
        exit 0
    fi
fi


# =================================== Main ====================================

# Define Okapi working mode
if ! FO_WORKMODE=$(whiptail --title "Okapi - Working mode" --radiolist \
  "Choose how Okapi should operate:" 20 78 4 -- \
  "cluster" "- for running in clustered mode/production" OFF \
  "dev" "- for running in develpment, single-node mode" ON \
  "deployment" "- for okapi deployment only. Clustered mode" OFF \
  "proxy" "- for proxy + discovery. Clustered mode" OFF 3>&1 1>&2 2>&3)
  then
    fo_cancel
fi

# Define okapi port
if ! FO_OKAPIPORT=$(whiptail --title "Okapi - Ports" --radiolist \
  "Define okapi port (and the range of non-IANA-registered subsequent ports for submodules)" 20 78 4 \
  "9130" "(default, 9131-9149)" ON \
  "10600" "(10601-10822)" OFF \
  "11400" "(11401-11752)" OFF 3>&1 1>&2 2>&3)
  then
    fo_cancel
  else
    # Handle options according to users choice
    case "$FO_OKAPIPORT" in
      9130)
        FO_PORTRANGE_START="9131"
        FO_PORTRANGE_END="9141"
        ;;
      10600)
        FO_PORTRANGE_START="10601"
        FO_PORTRANGE_END="10822"
        ;;
      11400)
        FO_PORTRANGE_START="11401"
        FO_PORTRANGE_END="11752"
        ;;
    esac
fi

# Storage backend
if ! whiptail --title "Okapi - Database" --yesno \
  "Use PostgreSQL as database backend?" 8 78
  then
    FO_DATABASE="inmemory"
  else
    FO_DATABASE="postgres"
    # Ask postgres questions
    # Server
    if ! FO_PGSERVER=$(whiptail --title "Okapi - PostgreSQL" --inputbox \
      "Provide postgres server address:" 8 78 localhost 3>&1 1>&2 2>&3)
      then
        fo_cancel
    fi
    # Port
    if ! FO_PGPORT=$(whiptail --title "Okapi - PostgreSQL" --inputbox \
      "Provide postgres server port:" 8 78 5432 3>&1 1>&2 2>&3)
      then
        fo_cancel
    fi
    # User
    if ! FO_PGUSER=$(whiptail --title "Okapi - PostgreSQL" --inputbox \
      "Provide postgres username:" 8 78 folio_okapi 3>&1 1>&2 2>&3)
      then
        fo_cancel
    fi
    # Database name
    if ! FO_PGDATABASE=$(whiptail --title "Okapi - PostgreSQL" --inputbox \
      "Provide postgres database name:" 8 78 folio_okapi 3>&1 1>&2 2>&3)
      then
        fo_cancel
    fi
    # Password
    if ! FO_PGPASSWD=$(whiptail --title "Okapi - PostgreSQL" --passwordbox \
      "Provide postgres password. Leaving it empty will result in a random string to be used." 8 78 3>&1 1>&2 2>&3)
      then
        fo_cancel
    fi
    # Use a random string for an empty password
    if [ "$FO_PGPASSWD" = "" ]
      then
        FO_PGPASSWD=$(</dev/urandom tr -dc 'A-Za-z0-9!#$%&()*+,-./:;<>?@[]^_`{|}~' | head -c 24)
      else
        # Strip forbidden characters to avoid problems
        FO_PGPASSWD=$(echo "$FO_PGPASSWD" | tr -dc 'A-Za-z0-9!#$%&()*+,-./:;<>?@[]^_`{|}~')
    fi
fi

# Copy example file as template
cp "$FO_EXAMPLE" "$FO_TEMP"
chown root:okapi "$FO_TEMP"
chmod 640 "$FO_TEMP"

# Change template with aquired information
sed -i "s/^role=.*/role=\"$FO_WORKMODE\"/g" "$FO_TEMP" && \
sed -i "s/^port=.*/port=\"$FO_OKAPIPORT\"/g" "$FO_TEMP" && \
sed -i "s/^port_start=.*/port_start=\"$FO_PORTRANGE_START\"/g" "$FO_TEMP" && \
sed -i "s/^port_end=.*/port_end=\"$FO_PORTRANGE_END\"/g" "$FO_TEMP" && \
sed -i "s/^host=.*/host=\"$(hostname -f)\"/g" "$FO_TEMP" && \
sed -i "s/^okapiurl=.*/okapiurl=\"http:\/\/$(hostname -f):$FO_OKAPIPORT\"/g" "$FO_TEMP" && \
sed -i "s/^storage=.*/storage=\"$FO_DATABASE\"/g" "$FO_TEMP" && \
# If postgres is used as database, set the database settings
if [ "$FO_DATABASE" = "postgres" ]
  then
    sed -i "s/^postgres_host=.*/postgres_host=\"$FO_PGSERVER\"/g" "$FO_TEMP" && \
    sed -i "s/^postgres_port=.*/postgres_port=\"$FO_PGPORT\"/g" "$FO_TEMP" && \
    sed -i "s/^postgres_username=.*/postgres_username=\"$FO_PGUSER\"/g" "$FO_TEMP" && \
    sed -i "s/^postgres_database=.*/postgres_database=\"$FO_PGDATABASE\"/g" "$FO_TEMP" && \
    sed -i "s'^postgres_password=.*'postgres_password=\"$FO_PGPASSWD\"'g" "$FO_TEMP"
    # Using a denominator that is already forbidden in the password
fi

# Move the temporary file to the config file
if [ "$?" = "0" ]
  then
    mv "$FO_TEMP" "$FO_CONFIG"
fi

# Now check if everything has worked out
if [ "$?" = "0" ]
  then
    whiptail --title "Okapi - Config" --msgbox \
      "Config created." 8 78
    # Exit for inmemory database
    if [ "$FO_DATABASE" = "inmemory" ]
      then
        exit 0
    fi
  else
    # Set color
    export NEWT_COLORS='root=,red'
    whiptail --title "Okapi - Setup error" --msgbox \
      "Config could not be created! Please copy example config from '$FO_EXAMPLE' to '$FO_CONFIG' and modify it manually." 8 78
    # Remove temp file
    rm -f "$FO_TEMP"
    exit 0
fi

# Database creation
if whiptail --title "Okapi - PostgreSQL setup" --yesno \
  "Set up PostgreSQL now?" 8 78
  then
    # Ask for superuser
    if ! FO_PGSUNAME=$(whiptail --title "Okapi - PostgreSQL setup" --inputbox \
      "Provide postgres superuser name:" 8 78 3>&1 1>&2 2>&3)
      then
        fo_pgcancel
    fi
    # Superuser password
    if ! PGPASSWORD=$(whiptail --title "Okapi - PostgreSQL setup" --passwordbox \
      "Provide postgres superuser password:" 8 78 3>&1 1>&2 2>&3)
      then
        fo_pgcancel
    fi
    # Secure the password for the user, so it can't leak on chatty PostgreSQL 
    # server logs
    # The password in PostgreSQL is stored like this:
    # md5passwd = "md5"+md5(cleartxtpasswd+user);
    # This won't work that easy with SCRAM-SHA-256, sadly
    FO_MD5SUM=$(echo -n "$FO_PGPASSWD$FO_PGUSER" | md5sum)
    # Prepare the temporary commands file
    touch "$FO_TEMP"
    chown root:root "$FO_TEMP"
    chmod 600 "$FO_TEMP"
    echo -e "CREATE ROLE $FO_PGUSER WITH PASSWORD 'md5${FO_MD5SUM:0:-3}' LOGIN;\nCREATE DATABASE $FO_PGDATABASE WITH OWNER $FO_PGUSER;" > "$FO_TEMP"
    # Set psql environment
    export PGCONNECT_TIMEOUT=5
    export PGPASSWORD
    # Run psql to create user and database (in subshell, for there's a bug which
    # prevents an infobox being displayed on other terminals emulators)
    (TERM=ansi; whiptail --title "Okapi - PostgreSQL setup" --infobox \
      "Connecting to '$FO_PGSERVER' as '$FO_PGSUNAME' to install user and database..." 8 78)
    if psql -U "$FO_PGSUNAME" -h "$FO_PGSERVER" -f "$FO_TEMP" postgres > /dev/null 2>&1
      then
        (TERM=ansi; whiptail --title "Okapi - PostgreSQL setup" --infobox \
          "Database setup complete" 8 78)
      else
        export NEWT_COLORS='root=,red'
        whiptail --title "Okapi - Abort" --msgbox \
          "Database setup ran into an error! Please check manually." 8 78
    fi
fi

# Remove temp file
rm -f "$FO_TEMP"

exit 0
