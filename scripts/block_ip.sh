#!/bin/bash
# Manual block IP
IP=$1
if [ -z "$IP" ]; then
  echo "Usage: ./block_ip.sh <IP>"
  exit 1
fi
sudo iptables -I INPUT -s $IP -j DROP
echo "$(date) - Blocked: $IP" >> /var/log/blocked_ips.log
echo "IP $IP berhasil diblokir"
