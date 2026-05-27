#!/bin/bash
# Manual unblock IP
IP=$1
if [ -z "$IP" ]; then
  echo "Usage: ./unblock_ip.sh <IP>"
  exit 1
fi
sudo iptables -D INPUT -s $IP -j DROP
echo "$(date) - Unblocked: $IP" >> /var/log/blocked_ips.log
echo "IP $IP berhasil di-unblock"
