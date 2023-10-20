if [[ -v CONTROLLER_SETTINGS ]]
then
    echo "The file controller_settings.sh has been already sourced"
    echo "Can not proceed"
    exit 0
fi

CONTROLLER_HOST=172.16.0.28
CONTROLLER_PORT=8082
REST_ADDRESS="http://$CONTROLLER_HOST:$CONTROLLER_PORT"
SSH_FILE=~/.ssh/mypair
export CONTROLLER_SETTINGS=
#
#END-OF-FILE
#
