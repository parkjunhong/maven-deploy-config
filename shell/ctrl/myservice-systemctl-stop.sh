#!/bin/bash

CMD="sudo systemctl stop ${service.name}"
echo $CMD
eval $CMD

echo
exit 0
 