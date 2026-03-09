#!/bin/sh

# -----------------------------------------------------------------------------
# generate-ovpn.sh — OpenVPN client config generator for OPNsense
#
# Extracts certificates from OPNsense config.xml and generates .ovpn files
# with support for multiple CA bundles (for smooth CA migration).
#
# Author: Denis Ivanov
# License: MIT
# -----------------------------------------------------------------------------

INVALID_CA=1
INVALID_USER=2
CA_NOT_FOUND=3
USER_NOT_FOUND=4

OPENVPN_HOST="put your host here"
OPENVPN_PORT=1194

OPENVPN_PARAMS="proto udp4
dev tun
persist-tun
persist-key
auth none
cipher none
data-ciphers none
pull-filter ignore \"redirect-gateway\"
client
resolv-retry infinite
remote $OPENVPN_HOST $OPENVPN_PORT
remote-cert-tls server
"

findCAId () {
  caName="$*"
  [ -z "$caName" ] && return $INVALID_CA
  caref=$(xmllint --xpath "//ca[descr=\"$caName\"]/refid/text()" /conf/config.xml 2>/dev/null)
  if [ -n "$caref" ]; then
    echo "$caref"
    return 0
  fi
  return $CA_NOT_FOUND
}

findCACrt() {
    caName="$*"
    [ -z "$caName" ] && return $INVALID_CA
    caCrt=$(xmllint --xpath "//ca[descr=\"$caName\"]/crt/text()" /conf/config.xml 2>/dev/null)
    if [ -n "$caCrt" ]; then
        echo "$caCrt"
        return 0
    fi
    return $CA_NOT_FOUND    
}

findUserCertSection() {
  caref="$1"
  shift
  [ -z "$caref" ] && return $INVALID_CA
  userName="$*"
  [ -z "$userName" ] && return $INVALID_USER
  result=$(xmllint --xpath "//cert[descr=\"$userName\" and caref=\"$caref\"]" /conf/config.xml 2>/dev/null)
  if [ -n "$result" ]; then
    echo "$result"
    return 0
  fi
  return $USER_NOT_FOUND
}

printUsage() {
  echo "Usage: $0 \"<user_name>\" \"<main_ca>\" \"<ca1>\" \"<ca2>\" ..."
  echo "Usage: $0 showca"
}

printCAs() {
  xmllint --xpath "//ca/descr/text()" /conf/config.xml
}

decode() {
    echo "$1" | base64 -d
}

generateConfigText() {
    caMain="$1"
    caAdditional="$2"
    userCrt="$3"
    userKey="$4"

    echo "$OPENVPN_PARAMS"
    echo "<ca>"
    oldIFS="$IFS"
    IFS=','
    for ca in "$caMain" $caAdditional; do
        caCrt=$(findCACrt "$ca")
        [ $? -ne 0 ] && echo $ca >&2 && IFS="$oldIFS" && return $CA_NOT_FOUND
        decode "$caCrt"
    done
    echo "</ca>"

    echo "<cert>"
    decode "$userCrt" 
    echo "</cert>"

    echo "<key>"
    decode "$userKey" 
    echo "</key>"
    IFS="$oldIFS"
}

join() {
  args=""
  for arg in "$@"; do
     [ -z "$args" ] && args="$arg" || args="$args,$arg"
  done
  echo "$args"
}

generate() {
  userName="$1"
  shift
  [ -z "$userName" ] && return $INVALID_USER
  
  caMain="$1"
  shift
  [ -z "$caMain" ] && return $INVALID_CA

  caAdditional=$(join "$@")
  caref=$(findCAId "$caMain")
  err=$?
  [ $err -ne 0 ] && echo $caMain && return $err

  user_cert=$(findUserCertSection "$caref" "$userName")
  err=$?
  [ $err -ne 0 ] && echo $userName && return $err

  userCrt=$(echo "$user_cert" | xmllint --xpath "//crt/text()" - 2>/dev/null)
  userKey=$(echo "$user_cert" | xmllint --xpath "//prv/text()" - 2>/dev/null)

  ovpnFile="$userName.ovpn"
  errData=$(generateConfigText "$caMain" "$caAdditional" "$userCrt" "$userKey"  2>&1 >$ovpnFile)
  err=$?
  echo $errData
  return $err
}

case $# in
  0) command=printUsage;;
  1) command=$1; shift;;
  *) command=generate;;
esac

case $command in
  printUsage) printUsage; exit 0;;

  showca) printCAs; exit 0;;

  generate) 
    userName="$1"
    shift
    echo Generate config for user: $userName
    errData=$(generate "$userName" "$@")
    err=$?
    [ $err -eq 0 ] && echo "Config has been generated" && exit 0;
    case $err in
      $INVALID_USER) echo "Invalid user name";;
      $INVALID_CA) echo "Invalid CA name";;
      $CA_NOT_FOUND) echo "CA \"$errData\" not found";;
      $USER_NOT_FOUND) echo "User \"$errData\" not found";;
    esac
    [ -f "$userName.ovpn" ] && rm "$userName.ovpn"
    exit $err
    ;;

  *) echo "invalid command: $command"; printUsage; exit 1;;
esac
