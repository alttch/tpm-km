#!/bin/bash

function print_err {
  printf "\e[91m" >&2
  echo $1
  printf "\e[0m" >&2
}

[ -f /usr/local/etc/tpm_km ] && source /usr/local/etc/tpm_km
[ -f /etc/tpm_km ] && source /etc/tpm_km

if [ ! $PCRS ] || [ ! $ADDRS ] || [ ! $KEYFILE ] || [ ! $TPM ]; then
  print_err "TPM params not loaded, config missing?"
  exit 11
fi

while [ ! $PIN ]; do
  PIN=$(dialog ${DIALOG_ARGS} --passwordbox "Define PIN:" 10 30 3>&1 1>&2 2>&3)
  PIN2=$(dialog ${DIALOG_ARGS} --passwordbox "Verify PIN:" 10 30 3>&1 1>&2 2>&3)
  [ ! $PIN ] || [ ! $PIN2 ] && exit 0
  if [ "x$PIN" != "x$PIN2" ]; then
    print_err "PINs don't match"
    PIN=
    sleep 1
  fi
done

CHECKED=1
for pcr in `echo ${PCRS} | tr "," "\n" | tr " " "\n"|sort -n|uniq`; do
  VAL=`tpm2_pcrlist -L sha256:${pcr} -T ${TPM} |tail -1|awk '{ print $3 }'`
  if [ `echo -n "x$VAL" |wc -c` -ne 65 ]; then
    print_err "Unable to check PCR ${pcr}"
    CHECKED=0
  elif [ $VAL == "0000000000000000000000000000000000000000000000000000000000000000" ]; then
    print_err "PCR ${pcr} is empty!"
    CHECKED=0
  fi
done

if [ $CHECKED -ne 1 ]; then
 echo
 print_err "Abort"
 exit 10
fi

KEY=`cat ${KEYFILE} | openssl enc -aes-256-cbc -pbkdf2 -k ${PIN} -base64`
if [ $? -ne 0 ]; then
  print_err "Unable to read ${KEYFILE}"
  exit 1
fi
L=${#PCRS[@]}
KEYLEN=$(echo -n $KEY|wc -c)
CHUNK_LEN=$(($KEYLEN/$L))
END=$(($L-1))
for i in $(seq 0 $END); do
  CS=$(($i*$CHUNK_LEN))
  [ $i -lt $END ] && CE=$(($CS+$CHUNK_LEN)) || CE=
  CS=$(($CS+1))
  CHUNK=`echo -n $KEY|cut -c$CS-$CE`
  pfile=$(mktemp /tmp/tpm-seal-policy.XXXXXXX)
  tpm2_createpolicy -P -L sha256:${PCRS[$i]} -f $pfile -T ${TPM}
  if [ $? -ne 0 ]; then
    print_err "Unable to create policy for ${PCRS[$i]}"
    exit 2
  fi
  tpm2_nvrelease -x ${ADDRS[$i]} -a 0x40000001 -T ${TPM} > /dev/null 2>&1
  tpm2_nvdefine -x ${ADDRS[$i]} -a 0x40000001 -L $pfile -s 255 -t "policyread|policywrite" -T ${TPM}
  if [ $? -ne 0 ]; then
    print_err "Unable to define nv for ${ADDRS[$i]}"
    rm -f $pfile
    exit 3
  fi
  echo -n $CHUNK | tpm2_nvwrite -x ${ADDRS[$i]} -a ${ADDRS[$i]} -L sha256:${PCRS[$i]} -T ${TPM}
  if [ $? -ne 0 ]; then
    print_err "Unable to write key part in ${ADDRS[$i]}, PCRS: ${PCRS[$i]}"
    rm -f $pfile
    exit 4
  fi
  rm -f $pfile
done
clear
printf "\e[92m"
which figlet > /dev/null && figlet -f small "KEY SEALED" || echo "KEY SEALED"
printf "\e[0m"
