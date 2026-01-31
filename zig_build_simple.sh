#!/usr/bin/env sh
zigwin build --summary failures 2>&1 | awk 'BEGIN{skip=0} {if(skip){skip=0; next} if($0 ~ /^error: /){skip=1; next} print}'
