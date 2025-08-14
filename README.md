# 目的
OSSなNOSであるRARE/freeRTRに無限の可能性があることを見出したい。  
CiscoライクなこのNOSでL3VPNの構築を試していく。  

# 前提
ネットワーク検証環境はcontainerlabを利用することを前提としています。

# 使い方
・デプロイ  
`git clone https://github.com/MizutoArakawa/freeRTR_InterAS_OptionC.git`  
`clab dep -t freeRTR_InterAS_OptionC/`  

・クリーンアップ削除  
`clab des -a -c`  

・ラボ表示  
`clab inspect --all`  

# 構築するもの
- freeRouterを使ってSR-MPLS網を構成し、L3VPNで通信可能にする  
   - L3VPNでAS間のLinkである Inter-AS OptionC を構築  

# Inter-AS OptionCについて
異なるAS間で経路情報を交換し、end-endの通信を行う方式  
本構成において、ASBRがRRの役割も引き受けている  
freeRtrのコンフィグの仕様に基づいた定義は以下の通りとする  

1. ASBR、が labeled ルートを交換する
2. ASBRはPEのIPv4 Loopback addressをBGP next hop addressとしてラベルを交換する
3. 各ドメインのPEに対するBGP next hop addressのラベル配布オプションとして、OSPFによるSR-MPLSを使用
4. AS間でのIPv4 Loopback addressのやり取りは別processなOSPFでアドバタイズし、BGPに再配布させる

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

# 実現したこと
・OSPF、BGPによるラベル転送  
・AS間の上り、下りルート制御  
　通常時のルート (上り、下り共に同一ルート)  
　　Aルート: host1_1 ～ ASBR1 ～ eASBR1 ～ host1_2  
　　Bルート: host2_1 ～ ASBR2 ～ eASBR2 ～ host2_2  
・OSPFのECMP(ちょっと特殊)  
・ACLによるhost端末からSR網内をハイド  

# いつか実現したいこと
- VPNv4 unicastのようなSAFIにVRFのRT値を注入させたVRF毎の通信  
- BGPのバックアップパスのインストール(PIC)  
- BFD、node protectionを利用した高速迂回ルーティング  
   - ※仮想環境のためリンクパススルー機能が無い以上、高速迂回は無理そう  
- コントローラを用いてPCEPを張り、PMによる遅延計算に基づいた上りトラフィック経路の最適化  
- BGP community値での制御  
- QoS(仮想環境でもやれるようになれたらいいな)  
- 装置やルーティングプロトコルのprocess立ち上がり時、max metricにする  
- OSPF立ち上がり時の救済プライオリティの設定  

# 論理設計
```
・リンクバンドル  
1xx: PE-P  
1x: P-ASBR, ePE-eASBR  
1: ASBR-eASBR  
5x: ASBR-ASBR, eASBR-eASBR  
30: CE向け  

・vrf definition  
sr-mpls網内: DEF_SEGROUT  

・ospf process num  
AS内: 10  
AS外: 20  

・ospf cost value  
PE-P: 2000  
P-ASBR, ePE-eASBR: 700  
ASBR-ASBR, eASBR-eASBR(process 10): 1300  
ASBR-ASBR, eASBR-eASBR(process 20): 900  
ASBR-eASBR: 3000  

・SRGB  
segrout 500 base 12000: 12000 ～ 12499  

・AS num  
eが付かない装置: 65000  
eが付く装置:     17000  


・ip address  
ospf 10  
AS 65000  
範囲: /20    255.255.240.0    4096    10.100.128.0～10.100.143.255  

AS 17000  
範囲: /20	255.255.240.0	4096	20.200.128.0～20.200.143.255  

ospf 20  
範囲: /28	255.255.255.240	16	10.10.186.0～10.10.186.15  

CE向け  
CE-A, eCE-A  
範囲: /29	255.255.255.248	8	100.50.80.0～100.50.80.7  

CE-B, eCE-B  
範囲: /29	255.255.255.248	8	100.50.81.0～100.50.81.7  


  links:  
    # AS65000 IGP  
    - endpoints: ["PE_A:eth2","P1:eth1"] 10.100.128.0/30   PE_A:10.100.128.1   P1:10.100.128.2   B100  
    - endpoints: ["PE_A:eth3","P2:eth1"] 10.100.128.4/30   PE_A:10.100.128.5   P2:10.100.128.6   B101  
    - endpoints: ["PE_B:eth2","P1:eth2"] 10.100.129.0/30   PE_B:10.100.129.1   P1:10.100.129.2   B110  
    - endpoints: ["PE_B:eth3","P2:eth2"] 10.100.129.4/30   PE_B:10.100.129.5   P2:10.100.129.6   B111  
    - endpoints: ["P1:eth3","ASBR1:eth1"] 10.100.135.0/30   P1:10.100.135.1   ASBR1:10.100.135.2   B10  
    - endpoints: ["P1:eth4","ASBR2:eth1"] 10.100.135.4/30   P1:10.100.135.5   ASBR2:10.100.135.6   B11  
    - endpoints: ["P2:eth3","ASBR1:eth2"] 10.100.136.0/30   P2:10.100.136.1   ASBR1:10.100.136.2   B17  
    - endpoints: ["P2:eth4","ASBR2:eth2"] 10.100.136.4/30   P2:10.100.136.5   ASBR2:10.100.136.6   B18  

    # ASBR 渡り  
    - endpoints: ["ASBR1:eth3","ASBR2:eth3"] 10.100.142.0/30   ASBR1:10.100.142.1   ASBR2:10.100.142.2   B50  
    - endpoints: ["ASBR1:eth4","ASBR2:eth4"] 10.10.186.8/30   ASBR1:10.10.186.9   ASBR2:10.10.186.10   B51  

    # AS間  
    - endpoints: ["ASBR1:eth5","eASBR1:eth5"] 10.10.186.0/30   ASBR1:10.10.186.1   eASBR1:10.10.186.2   B1  
    - endpoints: ["ASBR2:eth5","eASBR2:eth5"] 10.10.186.4/30   ASBR2:10.10.186.5   eASBR2:10.10.186.6   B1  

    # eASBR 渡り  
    - endpoints: ["eASBR1:eth3","eASBR2:eth3"] 20.200.142.0/30   eASBR1:20.200.142.1   eASBR2:20.200.142.2   B50  
    - endpoints: ["eASBR1:eth4","eASBR2:eth4"] 10.10.186.12/30   eASBR1:10.10.186.13   eASBR2:10.10.186.14   B51  

    # AS17000 IGP  
    - endpoints: ["eASBR1:eth1","ePE_A:eth2"] 20.200.135.0/30   eASBR1:20.200.135.1   ePE_A:20.200.135.2   B10  
    - endpoints: ["eASBR1:eth2","ePE_B:eth2"] 20.200.136.0/30   eASBR1:20.200.136.1   ePE_B:20.200.136.2   B17  
    - endpoints: ["eASBR2:eth1","ePE_A:eth3"] 20.200.135.4/30   eASBR2:20.200.135.5   ePE_A:20.200.135.6   B11  
    - endpoints: ["eASBR2:eth2","ePE_B:eth3"] 20.200.136.4/30   eASBR2:20.200.136.5   ePE_B:20.200.136.6   B18  

    # ユーザ向け  
    - endpoints: ["CE_A:eth1","PE_A:eth1"] 100.50.80.0/30   CE_A:100.50.80.1   PE_A:100.50.80.2   B30  
    - endpoints: ["CE_B:eth1","PE_B:eth1"] 100.50.81.0/30   CE_B:100.50.81.1   PE_B:100.50.81.2   B30  
    - endpoints: ["eCE_A:eth1","ePE_A:eth1"] 100.50.80.4/30   eCE_A:100.50.80.5   ePE_A:100.50.80.6   B30  
    - endpoints: ["eCE_B:eth1","ePE_B:eth1"] 100.50.81.4/30   eCE_B:100.50.81.5   ePE_B:100.50.81.6   B30  


・Loopback address  
Lo1  
AS65000  
範囲: /24    255.255.255.0    256    100.100.100.0～100.100.100.255  
PE_A:    100.100.100.1, SID 12001  
PE_B:    100.100.100.2, SID 12005  
P1:      100.100.100.10, SID 12010  
P2:      100.100.100.20, SID 12015  
ASBR1:  100.100.100.100, SID 12100  
ASBR2:  100.100.100.200, SID 12200  

AS17000  
範囲: /24    255.255.255.0    256    122.200.200.0～122.200.200.255  
eASBR1: 122.200.200.100, SID 12300  
eASBR2: 122.200.200.200, SID 12305  
ePE_A:   122.200.200.1, SID 12310  
ePE_B:   122.200.200.2, SID 12315  

Lo2 eBGP用  
ASBR1:  1.1.1.1  
ASBR2:  2.2.2.2  
eASBR1: 5.5.5.5  
eASBR2: 6.6.6.6  
```

## freeRouterの簡易コマンド集
#### 装置状態確認コマンド
```
show interfaces description
show ipv4 interface
ping <IP address> vrf <VRF名>    - VRF名を指定しないといけない
traceroute <IP address> vrf <VRF名>    - pingと同じ注意
show ipv4 route <VRF名>    - 全表示は不可
show router ospf4 100 redisted <unicast | multicast>
show router ospf4 100 computed unicast    - ospfで受け取ったものを表示
show vrf routing
show ipv4 labels <VRF名>
show running-config
show logging | exclude command
```

#### 設定コマンド
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
 ipv4 address <100.100.100.1> <255.255.255.255>

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

#### コンフィグ保存
`write`