#! /bin/sh

set +e

show_help()
{
    cat <<EOF
Usage:
    $0 [OPTIONS] <COMMANDS> [ARGS]

Commands:
    start         Start all lrs services and nginx.
    stop          Stop all lrs services and nginx.
    create:admin  Create default admin account.
EOF
exit 1
}

log ()
{
  echo "LRSCTL [INFO]: $1"
}

stop ()
{
    nginx -s stop
    pm2 delete all
}

start() {
  (
    cd /app || exit 1

    # ORIGINAL
    # npm --prefix /app/lrs-core run migrate
    # pm2 start pm2.json
    # nginx -g "daemon off;"

    # EXPEDIENT UNTIL FLUENTBIT IS ADDED
    pm2 start pm2.json
    nginx
    ls /root/.pm2/logs/*.log | xargs tail -n 300 -f
    # ls /root/.pm2/logs/*.log /var/log/nginx/*.log /var/log/morgan/*.log | xargs tail -n 300 -f
  )
}


create_admin()
{
  (
    cd /app || exit 1
    local organisation="Big Corp"
    local email="admin@email.com"
    local password="password123"
    
    node cli/dist/server createSiteAdmin "$email" "$organisation" "$password"
    log "Admin account created"
    log "====================="
    log "organisation:    $organisation"
    log "email:           $email"
    log "password:        $password"
  )
}

if [ "$1" = "stop" ]; then
  stop
elif [ "$1" = "start" ]; then
  start
elif [ "$1" = "create:admin" ]; then
  create_admin
else
  show_help
fi