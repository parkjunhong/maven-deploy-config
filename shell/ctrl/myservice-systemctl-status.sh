#!/bin/bash

CMD="sudo systemctl status ${service.name}"
echo $CMD
eval $CMD

echo
exit 0
 