#!/bin/bash

[ -f /usr/local/etc/tpm_km ] && source /usr/local/etc/tpm_km
[ -f /etc/tpm_km ] && source /etc/tpm_km

if [ ! $KEYFILE ]; then
  echo "TPM params not loaded, config missing?"
  exit 11
fi

if [ -f ${KEYFILE} ]; then
  echo "${KEYFILE} already exists. Aborting"
  exit 1
fi

KEY=`(tr -cd '[:alnum:]' < /dev/urandom | head -c128) 2>/dev/null`
touch ${KEYFILE} || exit 2
chmod 000 ${KEYFILE} || exit 3
echo -n $KEY > ${KEYFILE} || exit 4
printf "\e[92m"
which figlet > /dev/null && figlet -f small "KEY GENERATED" || echo "KEY GENERATED"
printf "\e[0m"
