# 目的
OSS NOSであるRARE/freeRTRに無限の可能性があることを見出したい。  
CiscoライクなこのNOSでL3VPNの構築を試していく。  

# 前提
ネットワーク検証環境はContainerlabの利用を前提としています。

### 【参考】インストール
- Containerlab
    - `curl -L http://containerlab.dev/setup | sudo bash -s "all"`
    - 必要なものが全てインストールされます。
- freeRouter
    - `git clone https://github.com/rare-freertr/freeRtr-containerlab.git`
    - `cd freeRtr-containerlab`
    - `docker build --no-cache -t freertr-containerlab:latest .`

# 使い方
### デプロイ  
`git clone https://github.com/MizutoArakawa/freeRTR_InterAS_OptionC.git`  
`clab dep -t freeRTR_InterAS_OptionC/`  

※ 前述の `freertr-containerlab:latest` イメージをビルドした前提です。  

##### 2025.06の検証の環境を使用したい場合
`docker load < freertr-2025-06.tar`  
`image: ghcr.io/rare-freertr/freertr-containerlab:main` を使用に変更  

### クリーンアップ削除  
`clab des -a -c`  

### ラボ表示  
`clab inspect --all`  

### ログイン
`username / password: rare`  

##### PE_A
`docker exec -it clab-freeRTR_InterAS-OptionC-PE_A telnet localhost 2323`  

##### PE_B
`docker exec -it clab-freeRTR_InterAS-OptionC-PE_B telnet localhost 2323`  

##### P1
`docker exec -it clab-freeRTR_InterAS-OptionC-P1 telnet localhost 2323`  

##### P2
`docker exec -it clab-freeRTR_InterAS-OptionC-P2 telnet localhost 2323`  

##### ASBR1
`docker exec -it clab-freeRTR_InterAS-OptionC-ASBR1 telnet localhost 2323`  

##### ASBR2
`docker exec -it clab-freeRTR_InterAS-OptionC-ASBR2 telnet localhost 2323`  

##### eASBR1
`docker exec -it clab-freeRTR_InterAS-OptionC-eASBR1 telnet localhost 2323`  

##### eASBR2
`docker exec -it clab-freeRTR_InterAS-OptionC-eASBR2 telnet localhost 2323`  

##### ePE_A
`docker exec -it clab-freeRTR_InterAS-OptionC-ePE_A telnet localhost 2323`  

##### ePE_B
`docker exec -it clab-freeRTR_InterAS-OptionC-ePE_B telnet localhost 2323`  

##### VPC1_1
`docker exec -it clab-freeRTR_InterAS-OptionC-VPC1_1 /bin/sh`  

##### VPC1_2
`docker exec -it clab-freeRTR_InterAS-OptionC-VPC1_2 /bin/sh`  

##### VPC2_1
`docker exec -it clab-freeRTR_InterAS-OptionC-VPC2_1 /bin/sh`  

##### VPC2_2
`docker exec -it clab-freeRTR_InterAS-OptionC-VPC2_2 /bin/sh`  

# 構築するもの
- freeRouterを用いたSR-MPLS網の構成とL3VPN通信  
- Inter-AS OptionCの構築 (AS間のラベル付き経路交換)  

### Inter-AS OptionCについて
異なるAS間で経路情報を交換し、End-to-Endの通信を行う方式  
本構成ではASBRがRR（Route Reflector）の役割も兼務する  
freeRouterのコンフィグの仕様に基づいた定義は以下の通りとする  

1. ASBR間でのラベル交換: ASBRがlabeledルートを交換
2. Next-hopの管理: PEのIPv4 LoopbackアドレスをBGP next hopとしてラベル交換を行う
3. ラベル配布: 各ドメインのPEに対して、OSPFによるSR-MPLS（Segment Routing）を使用
4. 再配布の活用: Loopbackアドレスのやり取りは別プロセスのOSPFでアドバタイズし、BGPに再配布

Ciscoが定義するものは下記  
```
・Route Reflectors exchange VPNv4 routes  
・ASBRs Exchange PE loopbacks (IPv4) with labels as these are BGP NH addresses  
・Eliminates LFIB duplication at ASBRs. ASBRs don’t hold VPNv4 prefix/label info.  
・Two Options for Label Distribution for BGP NH Addresses for PEs in each domain:  
　1. BGP IPv4 + Labels (RFC3107) – most preferred & recommended  
　2. IGP + LDP
・BGP exchange Label Advertisement Capability - Enables end-end LSP Paths  
・Subsequent Address Family Identifier (SAFI value 4) field is used to indicate that the NLRI contains a label  
・Disable Next-hop-self on eBGP RRs (peers)  
```

### 実現したこと
- OSPF、BGPによるラベル転送  
- AS間の上り、下りルート制御  
    - 通常時のルート (上り、下り共に同一ルート)  
    - Aルート: VPC1_1 ～ ASBR1 ～ eASBR1 ～ VPC1_2  
    - Bルート: VPC2_1 ～ ASBR2 ～ eASBR2 ～ VPC2_2  
- OSPFのECMP(ちょっと特殊)  
- ACLによるVPC端末からSR網内をハイド  

### いつか実現したいこと
- VPNv4 unicastのようなSAFIにVRFのRT値を注入させたVRF毎の通信  
- BGPのバックアップパスのインストール(PIC)  
- BFD、node protectionを利用した高速迂回ルーティング  
- コントローラを用いてPCEPを張り、PMによる遅延計算に基づいた上りトラフィック経路の最適化  
- BGP community値での制御  
- QoS(仮想環境でもやれるようになれたらいいな)  
- 装置やルーティングプロトコルのprocess立ち上がり時、max metricにする  
- OSPF立ち上がり時の救済プライオリティの設定  

### 論理設計

##### 1. 基本設定パラメータ

| 項目 | 設定内容 |
| --- | --- |
| VRF定義 | `DEF_SEGROUT` (SR-MPLS網内) |
| OSPFプロセス番号 | AS内: `10` / AS外: `20` |
| SRGB (segrout 500 base 12000) | 12000 ～ 12499 |
| AS番号 | eなし装置: `65000` / eあり装置: `64512` |

##### 2. リンクバンドル一覧

| リンクバンドル番号 | 対象リンク・機器 |
| --- | --- |
| 1xx | PE-P |
| 1x | P-ASBR, ePE-eASBR |
| 1 | ASBR-eASBR |
| 5x | ASBR-ASBR, eASBR-eASBR |
| 30 | CE(VPC)向け |

##### 3. OSPF コスト値一覧

| 該当箇所 | コスト値 |
| --- | --- |
| PE-P | 2000 |
| P-ASBR, ePE-eASBR | 700 |
| ASBR-ASBR, eASBR-eASBR (process 10) | 1300 |
| ASBR-ASBR, eASBR-eASBR (process 20) | 900 |
| ASBR-eASBR | 3000 |

##### 4. IPアドレス / サブネット範囲

| 区分 | プレフィックス | サブネットマスク | 最大ノード数 | 範囲 |
| --- | --- | --- | --- | --- |
| OSPF 10 (AS 65000) | /20 | 255.255.240.0 | 4096 | 10.100.128.0 ～ 10.100.143.255 |
| OSPF 10 (AS 64512) | /20 | 255.255.240.0 | 4096 | 10.200.128.0 ～ 10.200.143.255 |
| OSPF 20 | /28 | 255.255.255.240 | 16 | 10.10.186.0 ～ 10.10.186.15 |
| CE (VPC1_1, VPC1_2) | /29 | 255.255.255.248 | 8 | 10.50.80.0 ～ 10.50.80.7 |
| CE (VPC2_1, VPC2_2) | /29 | 255.255.255.248 | 8 | 10.50.81.0 ～ 10.50.81.7 |
| Lo1 (AS 65000) | /24 | 255.255.255.0 | 256 | 172.16.100.0 ～ 172.16.100.255 |
| Lo2 (AS 64512) | /24 | 255.255.255.0 | 256 | 172.16.200.0 ～ 172.16.200.255 |

##### 5. リンク詳細

| 区分 | エンドポイント | ネットワーク | デバイス1 IP | デバイス2 IP | リンクバンドル |
| --- | --- | --- | --- | --- | --- |
| AS 65000 IGP | PE_A:eth2 - P1:eth1 | 10.100.128.0/30 | 10.100.128.1 | 10.100.128.2 | B100 |
|  | PE_A:eth3 - P2:eth1 | 10.100.128.4/30 | 10.100.128.5 | 10.100.128.6 | B101 |
|  | PE_B:eth2 - P1:eth2 | 10.100.129.0/30 | 10.100.129.1 | 10.100.129.2 | B110 |
|  | PE_B:eth3 - P2:eth2 | 10.100.129.4/30 | 10.100.129.5 | 10.100.129.6 | B111 |
|  | P1:eth3 - ASBR1:eth1 | 10.100.135.0/30 | 10.100.135.1 | 10.100.135.2 | B10 |
|  | P1:eth4 - ASBR2:eth1 | 10.100.135.4/30 | 10.100.135.5 | 10.100.135.6 | B11 |
|  | P2:eth3 - ASBR1:eth2 | 10.100.136.0/30 | 10.100.136.1 | 10.100.136.2 | B17 |
|  | P2:eth4 - ASBR2:eth2 | 10.100.136.4/30 | 10.100.136.5 | 10.100.136.6 | B18 |
| ASBR渡り | ASBR1:eth3 - ASBR2:eth3 | 10.100.142.0/30 | 10.100.142.1 | 10.100.142.2 | B50 |
|  | ASBR1:eth4 - ASBR2:eth4 | 10.10.186.8/30 | 10.10.186.9 | 10.10.186.10 | B51 |
| AS間 | ASBR1:eth5 - eASBR1:eth5 | 10.10.186.0/30 | 10.10.186.1 | 10.10.186.2 | B1 |
|  | ASBR2:eth5 - eASBR2:eth5 | 10.10.186.4/30 | 10.10.186.5 | 10.10.186.6 | B1 |
| eASBR渡り | eASBR1:eth3 - eASBR2:eth3 | 10.200.142.0/30 | 10.200.142.1 | 10.200.142.2 | B50 |
|  | eASBR1:eth4 - eASBR2:eth4 | 10.10.186.12/30 | 10.10.186.13 | 10.10.186.14 | B51 |
| AS64512 IGP | eASBR1:eth1 - ePE_A:eth2 | 10.200.135.0/30 | 10.200.135.1 | 10.200.135.2 | B10 |
|  | eASBR1:eth2 - ePE_B:eth2 | 10.200.136.0/30 | 10.200.136.1 | 10.200.136.2 | B17 |
|  | eASBR2:eth1 - ePE_A:eth3 | 10.200.135.4/30 | 10.200.135.5 | 10.200.135.6 | B11 |
|  | eASBR2:eth2 - ePE_B:eth3 | 10.200.136.4/30 | 10.200.136.5 | 10.200.136.6 | B18 |
| ユーザ向け | VPC1_1:eth1 - PE_A:eth1 | 10.50.80.0/30 | 10.50.80.1 | 10.50.80.2 | B30 |
|  | VPC2_1:eth1 - PE_B:eth1 | 10.50.81.0/30 | 10.50.81.1 | 10.50.81.2 | B30 |
|  | VPC1_2:eth1 - ePE_A:eth1 | 10.50.80.4/30 | 10.50.80.5 | 10.50.80.6 | B30 |
|  | VPC2_2:eth1 - ePE_B:eth1 | 10.50.81.4/30 | 10.50.81.5 | 10.50.81.6 | B30 |

##### 6-1. Lo1 (ループバック1)

| AS番号 | 装置名 | IPアドレス | SID |
| --- | --- | --- | --- |
| AS 65000 | PE_A | 172.16.100.1 | 12001 |
|  | PE_B | 172.16.100.2 | 12005 |
|  | P1 | 172.16.100.10 | 12010 |
|  | P2 | 172.16.100.20 | 12015 |
|  | ASBR1 | 172.16.100.100 | 12100 |
|  | ASBR2 | 172.16.100.200 | 12200 |
| AS 64512 | eASBR1 | 172.16.200.100 | 12300 |
|  | eASBR2 | 172.16.200.200 | 12305 |
|  | ePE_A | 172.16.200.1 | 12310 |
|  | ePE_B | 172.16.200.2 | 12315 |

##### 6-2. Lo2 (eBGP用ループバック)

| 装置名 | IPアドレス |
| --- | --- |
| ASBR1 | 192.18.1.1 |
| ASBR2 | 192.18.2.2 |
| eASBR1 | 192.18.5.5 |
| eASBR2 | 192.18.6.6 |

# freeRouterの簡易コマンド集
### 装置状態確認コマンド

##### 画面操作

`terminal monitor`  
`terminal length 0`  
`terminal timestamps`  

##### ログ確認 & コンフィグ

`show logging`  
`show logging last <num>`  
`show logging | exclude command`  
`show running-config`  
`show running-config | include hostname`  

##### Ping

`ping <IP address> vrf <VRF名>`  
`traceroute <IP address> vrf <VRF名>`  

##### インタフェース & IPアドレス確認

`show interfaces description`  
`show ipv4 interface`  

##### OSPF

`show ipv4 ospf <process num> neighbor`  
`show ipv4 ospf <process num> route <area num>`  
`show router ospf4 <process num> computed unicast`  
`show ipv4 ospf <process num> database <area num>`  

##### BGP

`show ipv4 bgp <process num> summary`  
`show ipv4 bgp <process num> labeled summary`  
`show ipv4 bgp <process num> labeled privateas`  
`show router bgp4 <process num> computed unicast`  
`show router bgp4 <process num> redisted unicast`  

##### VRF

`show vrf routing`  
`show vrf traffic`  
`show vrf icmp`  

##### ラベル

`show ipv4 labels <VRF名>`  

### 設定コマンド
```
リンクバンドルをしたい場合は先に下記を実行して作成
bundle <num>
 ～snip～
 !
!
vrf definition <VRF名>
 rd 65000(AS num):100(ID num)
 rt-import 65000(AS num):100(ID num)
 rt-export 65000(AS num):100(ID num)
 !
!
access-list <list name>
 sequence <num> permit all <prefix> <mask> all <prefix etc> all
 sequence <num> deny all any all any all
 !
!
router ospf4 <process id>
 vrf <VRF名>    - VRFを設定しないとenable出来ない
 router-id 0.0.0.1(ルータID)
 traffeng-id 0.0.0.0(ID)
 area 0 enable
 area 0 segrout
 segrout <num1> base <num2>    - num1はSRGBの個数、num2は始まる数字(例: segrout 260 base 16000は16000から始まり、16259までとなる)
 redistribute connected
 area 0 spf-ecmp
 ecmp
 !
!
interface loopback<num>
 vrf forwarding <VRF name>
 ipv4 address <10.100.100.1> <255.255.255.255>

 router ospf4 <process num> enable
 router ospf4 <process num> area 0
 router ospf4 <process num> passive
 router ospf4 <process num> segrout node
 router ospf4 <process num> segrout index <SID>
　➝例) index 1で範囲が16000～16259とすると、16001ラベルが付与される
 !
!
interface <interface>
 bundle-group <num>
 carrier-delay <num>
 cdp enable
 !
!
interface bundle<num>
 mtu <num>
 vrf forwarding <VRF name>
 ipv4 address <10.100.128.1> <255.255.255.252 | /30>
 mpls enable    - enable/disable packet processing
 router ospf4 <process num> enable
 router ospf4 <process num> area 0
 router ospf4 <process num> cost <num>
 router ospf4 <process num> bfd
 !
!
router bgp4 <AS num>
 vrf <VRF名>
 local-as <自AS num>
 router-id <address>
 address-family <識別子>
 !
 template <name> remote-as <destAS num>
 template <name> local-as <自AS num>
 template <name> address-family <識別子>
 template <name> distance 200(iBGPなら自動で200 eBGPなら自動で20が入る)
 template <name> additional-path-rx <識別子>
 template <name> additional-path-tx <識別子>
 template <name> update-source loopback<num>
 template <name> segrout
 template <name> next-hop-unchanged
 !
 neighbor <dest ip address> template <name>
 !
 !
 redistribute connected
 advertise <prefix> route-policy <RPL name>
 exit
 !
!
```

### コンフィグ保存
`write`

# 参考資料・出典
本記事を執筆するにあたり、以下のサイトを参考にしました。<br>

- Containerlab : https://containerlab.dev/
- freeRouter : http://www.freertr.org/
- freeRouter（GitHub） ： https://github.com/rare-freertr/freeRtr-containerlab
- Inter-AS OptionC : https://www.cisco.com/c/en/us/support/docs/multiprotocol-label-switching-mpls/mpls/200523-Configuration-and-Verification-of-Layer.html
- Inter-AS OptionC : https://nsrc.org/workshops/2015/apricot2015/raw-attachment/wiki/Track3MPLS/9-Apriot_2015_Inter-AS.2.pdf

# 商標

- 「Docker」は、Docker, Inc.の米国およびその他の国における商標または登録商標です。
- 「Debian」は、Software in the Public Interest, Inc.の登録商標です。
- その他、本記事に記載されている会社名、製品名は、各社の商標または登録商標です。

# 免責事項

本記事に掲載された手法を実施した結果発生する損失・損害については責任を負いかねます。<br>
また、実際の通信事業用ネットワークを模擬する際、IPアドレスやホスト名、ポートコンベンション等は同じ、もしくは類似させるようなことはせず、推測されないような値にしてください。<br>