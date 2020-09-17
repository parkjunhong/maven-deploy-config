#!/bin/bash

CMD="sudo systemctl start ${service.name}"
echo $CMD
eval $CMD

echo
exit 0
 