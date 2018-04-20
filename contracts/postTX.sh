#!/bin/bash

# store arguments in a special array 
args=("$@") 
# get number of elements 
ELEMENTS=${#args[@]} 
 
# echo each element in array  
# for loop 
for (( i=0;i<$ELEMENTS;i++)); do 
    echo ${args[${i}]} 
done

if [[ $# -eq 0 ]]
then echo >&2 "Must supply a transaction spec file name"; exit 1
fi

imgName=teamfae/posttx
if [[ -n $FAE_VERSION ]]
then imgName=$imgName:$FAE_VERSION
fi

declare -a envlist
n=0
while true; do
  case $1 in
    -e|--env-list|--env-file)
      envlist[$n]=$1
      envlist[$n + 1]=$2
      let n+=2
      shift 2
      ;;
    *) break ;;
  esac
done

cd contracts
txfile=$(basename $1)
shift

docker run \
  --rm \
  --network host \
  --mount type=bind,src=$PWD,dst=/txs/,readonly \
  "${envlist[@]}" $imgName $txfile $@

