#!/bin/bash

# Copyright (c) 2015, Fusl Dash <fusl@meo.ws>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -e

CTID=$(echo "$1" | egrep -o '^[0-9]+$')

if [ "x$CTID" == x" ]; then
	Usage: "$0 <CTID>"
	exit 1
fi

tmpfile=$(mktemp -u)

status=$(vzctl status "$CTID" | fgrep -q running; echo -n $?)

cp -f "/etc/vz/conf/$CTID.conf" "/etc/vz/conf/ve-999$CTID.conf-sample"
sed -i "s|/vz/root/$CTID|/vz/root/999$CTID|" "/etc/vz/conf/ve-999$CTID.conf-sample"
sed -i "s|/vz/private/$CTID|/vz/private/999$CTID|" "/etc/vz/conf/ve-999$CTID.conf-sample"
# todo: find out if we need that or if the automatic detection of vzctl's ploop creation is enough for us,
#  maybe create a function that reads the current size and then limits it accordingly?
#  anyway, for now we just stick with removing the diskinodes information, if you need it you can always comment out this line so it will be passed to ploop
sed -i "s|^DISKINODES=|# DISKINODES=|" "/etc/vz/conf/ve-999$CTID.conf-sample"
vzctl create "999$CTID" --ostemplate centos-6-x86_64 --config "999$CTID" --layout ploop
vzctl mount "999$CTID"
vzctl mount "$CTID" || true
find "/vz/root/999$CTID/" -mindepth 1 -delete
rsync -axHAXS                 --progress --stats --numeric-ids          "/vz/root/$CTID/" "/vz/root/999$CTID/" || true
rsync -axHAXS --append-verify --progress --stats --numeric-ids --delete "/vz/root/$CTID/" "/vz/root/999$CTID/" || true
vzctl chkpnt "$CTID" --dumpfile "$tmpfile" || true
vzctl stop "$CTID" || true
vzctl stop "$CTID" --fast || true
vzctl set "$CTID" --disabled=yes --save
vzctl mount "$CTID" || true
rsync -axHAXS --append-verify --progress --stats --numeric-ids --delete "/vz/root/$CTID/" "/vz/root/999$CTID/" && (
        # only run this part of the code if the last rsync exited without error so we can make sure that nothing went wrong
        vzctl umount "$CTID"
        vzctl umount "999$CTID"
        mv "/vz/private/$CTID" "/vz/private/$CTID.simfs"
        mv "/vz/private/999$CTID" "/vz/private/$CTID"
) || (
        # just umount the container without moving the directories since something went wrong at the last rsync
		#  (e.g. source file system too large, files changed or vanished while copying, etc. -- latter should never happen because the container is stopped)
        vzctl umount "$CTID"
        vzctl umount "999$CTID"
)
vzctl set "$CTID" --disabled=no --save
if [ "$status" == "0" ]; then
        test -f "$tmpfile" && vzctl restore "$CTID" --dumpfile "$tmpfile" || vzctl start "$CTID"
fi
vzctl destroy "999$CTID"
rm -f "/etc/vz/conf/ve-999$CTID.conf-sample"