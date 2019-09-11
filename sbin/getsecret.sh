#!/bin/bash

[ -f /usr/local/etc/tpm_km ] && source /usr/local/etc/tpm_km
[ -f /etc/tpm_km ] && source /etc/tpm_km

if [ ! $PCRS ] || [ ! $ADDRS ]; then
  echo "TPM params not loaded, config missing?" >&2
  exit 11
fi

KEY=
SUCCESS=1

for i in {0..1}; do
  K=`tpm2_nvread -x ${ADDRS[$i]} -a ${ADDRS[$i]} -L sha256:${PCRS[$i]} | tr -d '\0'`
  if [ $? -ne 0 ] || [ ! "$K" ]; then
    printf "\e[91m" >&2
    echo "Unable to read key file part $(($i + 1))" >&2
    SUCCESS=0
    break
  else
    KEY=${KEY}${K}
  fi
done

if [ $SUCCESS -eq 1 ]; then
  [ ! "$PIN" ] && PIN=$(dialog --clear --insecure --passwordbox "PIN:" 10 30 3>&1 1>&2 2>&3)
  KDEC=`echo $KEY | openssl enc -d -aes-256-cbc -pbkdf2 -k ${PIN} -base64 | tr -d '\0'`
  if [ $? -eq 0 ]; then
    echo -n $KDEC
    exit
  fi
  printf "\e[91m" >&2
  echo "Invalid PIN" >&2
fi
echo >&2
echo "Can't obtain key from TPM" >&2
sleep 2
printf "\e[0m" >&2
PW=$(dialog --clear --insecure --passwordbox "Decrypt password:" 10 40 3>&1 1>&2 2>&3)
echo -n ${PW}
exit 0
