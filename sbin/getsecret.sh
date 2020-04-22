#!/bin/bash

[ -f /usr/local/etc/tpm_km ] && source /usr/local/etc/tpm_km
[ -f /etc/tpm_km ] && source /etc/tpm_km

if [ -z "$PCRS" ] || [ -z "$ADDRS" ] || [ -z "$TPM" ]; then
  echo "TPM params not loaded, config missing?" >&2
  exit 11
fi

KEY=
SUCCESS=1

L=${#PCRS[@]}
END=$((L-1))
for i in $(seq 0 $END); do
  if K=$(tpm2_nvread -P pcr:sha256:"${PCRS[$i]}" "${ADDRS[$i]}" \
    -T "${TPM}" | tr -d '\0') && [ "$K" ]; then
    KEY="${KEY}${K}"
  else
    printf "\\e[91m" >&2
    echo "Unable to read key file part $((i + 1))" >&2
    SUCCESS=0
    break
  fi
done

if [ $SUCCESS -eq 1 ]; then
  [ ! "$PIN" ] && PIN=$(dialog ${DIALOG_ARGS} --passwordbox "PIN:" 10 30 3>&1 1>&2 2>&3)
  if [ "$PIN" ]; then
    if KDEC=$(echo "$KEY" | \
        openssl enc -d -aes-256-cbc -pbkdf2 -k "${PIN}" -base64 | tr -d '\0'); then
      echo -n "$KDEC"
      exit
    fi
    printf "\\e[91m" >&2
    echo "Invalid PIN" >&2
  fi
fi
echo >&2
echo "Can't obtain key from TPM" >&2
sleep 2
printf "\\e[0m" >&2
PW=$(dialog ${DIALOG_ARGS} --passwordbox "Decrypt password:" 10 40 3>&1 1>&2 2>&3)
echo -n "${PW}"
exit 0
