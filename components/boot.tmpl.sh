#!/bin/bash

curl --fail --connect-timeout 3 http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key > /tmp/id_rsa.pub
if [ $? -ne 0 ]; then
	echo {{ username }}:{{ password }} | /usr/sbin/chpasswd
fi

{{ CACommand }}