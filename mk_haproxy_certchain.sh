#!/bin/bash
CERTBOT=/usr/bin/certbot
HAPROXY=/usr/sbin/haproxy
HAPROXYCONFIG=/etc/haproxy/haproxy.cfg

NEWCERTHOST=$1

CERTBOTARGS="certonly --standalone --preferred-challenges http --http-01-port 8888 -d ${NEWCERTHOST}"
CERTBOTRENEWARGS="renew"

LECERTPATH=/etc/letsencrypt/live
HACERTPATH=/etc/haproxy/ssl

KEYFILE=$LECERTPATH/$NEWCERTHOST/privkey.pem
CERTFILE=$LECERTPATH/$NEWCERTHOST/fullchain.pem

HACOMBINEDCERT=$HACERTPATH/$NEWCERTHOST.combined.crt

if [[ -z $NEWCERTHOST ]]; then
  # cert exists, so attempt renew
  echo "attempting to renew all certificates"
  $CERTBOT $CERTBOTRENEWARGS --renew-hook "touch /tmp/le_certs_renewed.flag"
  if [[ -f /tmp/le_certs_renewed.flag ]]; then
    # some certs were renewed, so format them for haproxy and reload
    for DOMAIN in $(ls $LECERTPATH); do
      cat "$LECERTPATH/live/$DOMAIN/fullchain.pem" "$LECERTPATH/live/$DOMAIN/privkey.pem" > "$HACERTPATH/$DOMAIN.combined.crt"
    done
    $HAPROXY -c -f $HAPROXYCONFIG
    if [ $? -eq 0 ]; then
      systemctl reload haproxy
    else
      echo "haproxy config test failed"
    fi
    rm -f /tmp/le_certs_renewed.flag
  else
    echo "no new certificates"
  fi 
else
  echo "Requesting new certificate for $NEWCERTHOST"
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
fi
