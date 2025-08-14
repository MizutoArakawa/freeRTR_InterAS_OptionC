#!/bin/ash

# 設定するインターフェースとIPアドレス
INTERFACE="eth1"
IP_ADDRESS="100.50.81.5"
SUBNET_MASK="255.255.255.252"
BROADCAST_ADDRESS="100.50.81.7"
GATEWAY_ADDRESS="100.50.81.6"

# インターフェースにIPアドレスとブロードキャストアドレスを設定
echo "Setting IP address $IP_ADDRESS/$SUBNET_MASK and broadcast $BROADCAST_ADDRESS on $INTERFACE"
ip addr add $IP_ADDRESS/$SUBNET_MASK broadcast $BROADCAST_ADDRESS dev $INTERFACE

# インターフェースを有効化
echo "Bringing up $INTERFACE"
ip link set $INTERFACE up

# デフォルトゲートウェイの設定
ip route del default
ip route add default via $GATEWAY_ADDRESS dev $INTERFACE
