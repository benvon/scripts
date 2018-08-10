#!/bin/bash
CERTBOT=/usr/bin/certbot
HAPROXY=/usr/sbin/haproxy
HAPROXYCONFIG=/etc/haproxy/haproxy.cfg

CERTHOST=$1

if [[ -z $CERTHOST ]]; then
  echo "missing host argument"
  exit 1;
fi

CERTBOTARGS="certonly --standalone --preferred-challenges http --http-01-port 9999 -d ${CERTHOST}"

LECERTPATH=/etc/letsencrypt/live
HACERTPATH=/etc/haproxy/ssl

KEYFILE=$LECERTPATH/$CERTHOST/privkey.pem
CERTFILE=$LECERTPATH/$CERTHOST/fullchain.pem

HACOMBINEDCERT=$HACERTPATH/$CERTHOST.combined.crt

if [[ ! -f $CERTFILE ]]; then
  # Cert doesn't exist, so get a new one
  $CERTBOT $CERTBOTARGS 
  cat $CERTFILE $KEYFILE > $HACOMBINEDCERT  
  # Test haproxy config
  $HAPROXY -c -f $HAPROXYCONFIG
  if [ $? = 0 ]; then
    systemctl reload haproxy
  else
    echo "haproxy config test failed"
  fi
else
  cat $CERTFILE $KEYFILE > $HACOMBINEDCERT
  $HAPROXY -c -f $HAPROXYCONFIG
  if [ $? -eq 0 ]; then
    systemctl reload haproxy
  else
    echo "haproxy config test failed"
  fi
fi

#cat /etc/letsencrypt/live/wrangler.benvon.net/fullchain.pem /etc/letsencrypt/live/wrangler.benvon.net/privkey.pem > /etc/haproxy/ssl/wrangler.benvon.net.combined.crt
