#!/bin/bash
TOKEN=$TOKEN
./actions-runner/config.sh --unattended --url https://github.com/dgolbourn/eiko --token ${TOKEN}

cleanup(){
    ./config.sh remove --unattended --token ${TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./actions-runner/run.sh
wait $!
