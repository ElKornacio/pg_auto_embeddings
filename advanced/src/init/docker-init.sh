#! /bin/bash

# Check if the user exists, if not, create it
if ! su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$PG_USERNAME'\"" | grep -q 1; then
  echo "User $PG_USERNAME does not exist, creating..."
  su postgres -c "createuser -d -P $PG_USERNAME" <<EOF
$PG_PASSWORD
$PG_PASSWORD
EOF
fi

# Check if the database exists, if not, create it
if ! su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='pgae'\"" | grep -q 1; then
  echo "Database pgae does not exist, creating..."
  su postgres -c "createdb -O $PG_USERNAME pgae"
fi

# set password for user
su postgres -c "psql -c \"ALTER USER $PG_USERNAME WITH PASSWORD '$PG_PASSWORD';\""
echo "Password for user $PG_USERNAME updated"

# make this user superuser
su postgres -c "psql -c \"ALTER USER $PG_USERNAME WITH SUPERUSER;\""
echo "User $PG_USERNAME is now superuser"
