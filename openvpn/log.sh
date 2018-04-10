#!/bin/bash
LOGS=`readlink -f /var/log/openvpn/*`

JSON="{ \"data\":["
SEP=""
  for LOG in $LOGS ; do
    JSON=$JSON"$SEP{\"{#NAME}\":\"$LOG\"}"
    SEP=", "
done
JSON=$JSON"]}"
echo $JSON
exit 0
