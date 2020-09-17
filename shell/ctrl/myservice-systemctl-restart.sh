#!/bin/bash

CMD="sudo systemctl restart ${service.name}"
echo $CMD
eval $CMD

echo
exit 0
 