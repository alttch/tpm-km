#!/bin/bash

function print_err {
  printf "\\e[91m" >&2
  echo "$1"
  printf "\\e[0m" >&2
}

[ -f /usr/local/etc/tpm_km ] && source /usr/local/etc/tpm_km
[ -f /etc/tpm_km ] && source /etc/tpm_km

if [ -z "$PCRS" ] || [ -z "$ADDRS" ] || [ -z "$KEYFILE" ] || [ -z "$TPM" ]; then
  print_err "TPM params not loaded, config missing?"
  exit 11
fi

CHECKED=1
for pcr in $(echo "${PCRS[@]}" | tr "," "\\n" | tr " " "\\n"|sort -n|uniq); do
  VAL=$(tpm2_pcrread sha256:"${pcr}" -T "${TPM}" |tail -1|cut -dx -f2)
  if [ ${#VAL} -ne 64 ]; then
    print_err "Unable to check PCR ${pcr}"
    CHECKED=0
  elif [ "$VAL" == "0000000000000000000000000000000000000000000000000000000000000000" ]; then
    print_err "PCR ${pcr} is empty!"
    CHECKED=0
  fi
done

if [ $CHECKED -ne 1 ]; then
 echo
 print_err "Abort"
 exit 10
fi

PIN=
[ -f /usr/local/etc/tpm_sealpin ] && PIN=$(cat /usr/local/etc/tpm_sealpin)
while [ -z "$PIN" ]; do
  PIN=$(dialog ${DIALOG_ARGS} --passwordbox "Define PIN:" 10 30 3>&1 1>&2 2>&3)
  PIN2=$(dialog ${DIALOG_ARGS} --passwordbox "Verify PIN:" 10 30 3>&1 1>&2 2>&3)
  [ -z "$PIN" ] || [ -z "$PIN2" ] && exit 0
  if [ "$PIN" != "$PIN2" ]; then
    print_err "PINs don't match"
    PIN=
    sleep 1
  fi
done

clear

if ! KEY=$(openssl enc -aes-256-cbc \
      -pbkdf2 -k "${PIN}" -base64 < $KEYFILE | tr -d "\n" ); then
  print_err "Unable to read ${KEYFILE}"
  exit 1
fi
L=${#PCRS[@]}
KEYLEN=${#KEY}
CHUNK_LEN=$((KEYLEN/L))
END=$((L-1))
for i in $(seq 0 $END); do
  CS=$((i*CHUNK_LEN))
  [ "$i" -lt "$END" ] && CE=$((CS+CHUNK_LEN)) || CE=
  CS=$((CS+1))
  CHUNK=$(echo -n "$KEY"|cut -c$CS-$CE)
  pfile=$(mktemp /tmp/tpm-seal-policy.XXXXXXX)
  if ! tpm2_createpolicy --policy-pcr -l sha256:"${PCRS[$i]}" -L "$pfile" -T "${TPM}"; then
    print_err "Unable to create policy for ${PCRS[$i]}"
    exit 2
  fi
  tpm2_nvundefine -T "${TPM}" "${ADDRS[$i]}" > /dev/null 2>&1
  if ! tpm2_nvdefine -L "$pfile" -s 255 -a "policyread|policywrite" -T "${TPM}" "${ADDRS[$i]}"; then
    print_err "Unable to define nv for ${ADDRS[$i]}"
    rm -f "$pfile"
    exit 3
  fi
  if ! echo -n "$CHUNK" | tpm2_nvwrite -i - -T "${TPM}" -P pcr:sha256:"${PCRS[$i]}" "${ADDRS[$i]}"; then
    print_err "Unable to write key part in ${ADDRS[$i]}, PCRS: ${PCRS[$i]}"
    rm -f "$pfile"
    exit 4
  fi
  rm -f "$pfile"
done
printf "\\e[92m"
command -v figlet > /dev/null && figlet -f small "KEY SEALED" || echo "KEY SEALED"
printf "\\e[0m"
