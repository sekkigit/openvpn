#!/bin/bash

#VAR
ADMINUSER="firstname-lastname"
COUNTRY="Croatia"
CITY="Rijeka"
ORG="SekiTEH"
EMAIL="info@sekiteh.xyz"
PUBIP=$(curl ifconfig.me)
NETADAPT=$(ip route | grep default | sed -e "s/^.*dev.//" -e "s/.proto.*//")
COMPANY="name"

apt remove needrestart -y

# Import the GPG key
wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg|apt-key add -

# Create the repository file
echo deb http://build.openvpn.net/debian/openvpn/stable bionic main | tee /etc/apt/sources.list.d/openvpn- aptrepo.list

# Update apt and install OpenVPN
apt update && apt install openvpn -y


# Download & extract EasyRSA
mkdir /etc/easy-rsa
wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz 
tar xf EasyRSA-unix-v3.0.6.tgz -C /etc/easy-rsa
mv /etc/easy-rsa/EasyRSA-v3.0.6/* /etc/easy-rsa
rm -rf /etc/easy-rsa/EasyRSA-v3.0.6
rm EasyRSA-unix-v3.0.6.tgz


# Configure your EasyRSA environment variables file
cat <<EOF > /etc/easy-rsa/vars
set_var EASYRSA_REQ_COUNTRY     "$COUNTRY"
set_var EASYRSA_REQ_PROVINCE    "$COUNTRY"
set_var EASYRSA_REQ_CITY        "$CITY"
set_var EASYRSA_REQ_ORG         "$ORG"
set_var EASYRSA_REQ_EMAIL       "$EMAIL"
set_var EASYRSA_REQ_OU          "RD"
set_var EASYRSA_KEY_SIZE        2048 #4096
EOF

cd /home/"${SUDO_USER:-$USER}"
# Initialize the PKI Structure for EasyRSA
/etc/easy-rsa/easyrsa init-pki
sleep 2s

###NOTE#################
echo -e "\e[92m First step: \e[0m"
echo -e "\e[92m   - Enter PEM pass phrase \e[0m"
echo -e "\e[92m   - press enter at Common Name \e[0m"
echo

sleep 2s
# Create the CA Certificate
echo -e "\e[92m 25 sec to enter pass \e[0m"
echo {,} | /etc/easy-rsa/easyrsa build-ca nopass                                    # On NEW ubuntu it will ask you to set password  
sleep 25s
                                                                                    # press enter at Common Name
###NOTE#################
echo -e "\e[92m Next step: \e[0m"
echo -e "\e[92m   - press enter at Common Name \e[0m"
echo -e "\e[92m   - on NEW ubuntu set password \e[0m"
echo

# Create your OpenVPN server certificate request, sign the request, and generate the key and copy to OpenVPN
echo {,} | /etc/easy-rsa/easyrsa gen-req "$COMPANY"-vpn nopass                      # press enter at Common Name
sleep 2s
echo -e "\e[92m 20 sec to enter pass \e[0m"
echo yes | /etc/easy-rsa/easyrsa sign-req server "$COMPANY"-vpn nopass              # type yes
                                                                                    # On NEW ubuntu it will ask you to set password
sleep 20s
cp /home/"${SUDO_USER:-$USER}"/{pki/issued/"$COMPANY"-vpn.crt,pki/private/"$COMPANY"-vpn.key,pki/ca.crt} /etc/openvpn/

# Create the Encryption Key that will be used during the key exchange, create a HMAC signature to further strengthen TLS in OpenVPN
/etc/easy-rsa/easyrsa gen-dh                                                        # this can take up to 10-15 min
sleep 2s

echo -e "\e[92m 20 sec to enter pass \e[0m"
/etc/easy-rsa/easyrsa gen-crl
sleep 20s

cp /home/"${SUDO_USER:-$USER}"/pki/crl.pem /etc/openvpn/
openvpn --genkey --secret "/home/${SUDO_USER:-$USER}/ta.key"
cp /home/"${SUDO_USER:-$USER}"/ta.key /etc/openvpn
cp /home/"${SUDO_USER:-$USER}"/pki/dh.pem /etc/openvpn

# Create your OpenVPN Server Configuration
mkdir -p /etc/openvpn/client-configs/{files,keys}

###################################
# on old ubuntu let this 3 lines
#cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz /etc/openvpn/"$COMPANY"-vpn.conf.gz
#cd /etc/openvpn/
#gunzip "$COMPANY"-vpn.conf.gz

# on NEW ubuntu comment above 3 lines and uncomment below one
cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf /etc/openvpn/"$COMPANY"-vpn.conf
###################################

cp /home/"${SUDO_USER:-$USER}"/{ta.key,pki/ca.crt} /etc/openvpn/client-configs/keys/
groupadd nobody                                                                    # if you use nobody group in config this must be applyed

cat <<EOF > /etc/openvpn/"$COMPANY"-vpn.conf
;local a.b.c.d
port 1194
;proto tcp
proto udp
;dev tap
dev tun
;dev-node MyTap
ca ca.crt
cert $COMPANY-vpn.crt
key $COMPANY-vpn.key 
dh dh.pem
;topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp.txt
;server-bridge 10.8.0.4 255.255.255.0 10.8.0.50 10.8.0.100
;server-bridge
;push "route 192.168.10.0 255.255.255.0"
;push "route 192.168.20.0 255.255.255.0"
;client-config-dir ccd
;route 192.168.40.128 255.255.255.248
;client-config-dir ccd
;route 10.9.0.0 255.255.255.252
;learn-address ./script
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
;client-to-client
;duplicate-cn
keepalive 10 120
tls-auth ta.key 0
cipher AES-256-CBC
;compress lz4-v2
;push "compress lz4-v2"
;comp-lzo
;max-clients 100
user nobody
group nobody
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
log /var/log/openvpn/openvpn.log
;log-append /var/log/openvpn/openvpn.log
verb 3
;mute 20
#explicit-exit-notify 1
crl-verify /etc/openvpn/crl.pem
key-direction 0
auth SHA256
sndbuf 393216
rcvbuf 393216
push "sndbuf 393216"
push "rcvbuf 393216"
txqueuelen 10000
EOF

# Create the client base configuration
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf /etc/openvpn/client-configs/base.conf
cat <<EOF > /etc/openvpn/client-configs/base.conf
client
;dev tap
dev tun                                                                 # Sometimes this can make a trouble 
;dev-node MyTap
;proto tcp
proto udp
remote $PUBIP 1194    # SET IP of server
;remote my-server-2 1194
;remote-random
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
;http-proxy-retry # retry on connection failures
;http-proxy [proxy server] [proxy port #]
;mute-replay-warnings
#ca ca.crt
#cert client.crt
#key client.key
remote-cert-tls server
cipher AES-256-CBC
verb 3
;mute 20
fragment 0
key-direction 1
mssfix 0
auth SHA256
EOF

# The Certificate Creation Script
cat <<EOF > /root/create_vpn_user
#!/bin/bash

VPNUSER=\${1,,}
export EASYRSA_REQ_CN=\$VPNUSER
OUTPUT_DIR=/etc/openvpn/client-configs/files
KEY_DIR=/etc/openvpn/client-configs/keys
BASE_CONFIG=/etc/openvpn/client-configs/base.conf
OPENVPN_DIR=/etc/openvpn

EASYRSA_DIR=/home/"\${SUDO_USER:-\$USER}"

if [ "\$VPNUSER" = '' ]; then
echo "Usage: ./create_vpn_user firstname-lastname"
exit 1

else

echo "Creating certificate for \$VPNUSER"

/etc/easy-rsa/easyrsa --batch gen-req \$VPNUSER nopass
/etc/easy-rsa/easyrsa --batch sign-req client \$VPNUSER
cp \$EASYRSA_DIR/pki/private/\$VPNUSER.key /etc/openvpn/client-configs/keys/

cp \$EASYRSA_DIR/pki/issued/\$VPNUSER.crt /etc/openvpn/client-configs/keys/

cd \$OPENVPN_DIR/client-configs/
# First argument: Client identifier
cat \${BASE_CONFIG} <(echo -e '<ca>') \${KEY_DIR}/ca.crt <(echo -e '</ca>\n<cert>') \${KEY_DIR}/\${1}.crt <(echo -e '</cert>\n<key>') \${KEY_DIR}/\${1}.key <(echo -e '</key>\n<tls-auth>') \${KEY_DIR}/ta.key <(echo -e '</tls-auth>') > \${OUTPUT_DIR}/\$VPNUSER.ovpn

gzip \$OUTPUT_DIR/\$VPNUSER.ovpn

echo "***** Here is your link which holds configuration for open vpn *****"
curl -F "file=@\$OUTPUT_DIR/\$VPNUSER.ovpn.gz" https://file.io/?expires=1d | sed 's/^.*https/https/' | sed 's/\","expires.*//'
echo ""

rm \$OUTPUT_DIR/\$VPNUSER.ovpn.gz

echo "Generating new Certificate Revocation List (CRL)."
cd \$EASYRSA_DIR
/etc/easy-rsa/easyrsa gen-crl
cp \$EASYRSA_DIR/pki/crl.pem \$OPENVPN_DIR/crl.pem
systemctl restart openvpn@$COMPANY-vpn

sleep 5

echo "Displaying connected users:"
cat /var/log/openvpn/openvpn-status.log | sed '/ROUTING/q'| head -n -1

fi

EOF

chmod +x /root/create_vpn_user

# Certificate Revocation Script
cat <<EOF > /root/revoke_vpn_user
#!/bin/bash

VPNUSER=\${1,,}
echo \$VPNUSER
export EASYRSA_REQ_CN=\$VPNUSER
KEY_DIR=/etc/openvpn/client-configs/keys
OUTPUT_DIR=/etc/openvpn/client-configs/files
BASE_CONFIG=/etc/openvpn/client-configs/base.conf
OPENVPN_DIR=/etc/openvpn

EASYRSA_DIR=/home/"\${SUDO_USER:-\$USER}"

if [ "\$VPNUSER" = '' ]; then
echo "Usage: ./revoke_vpn_user firstname-lastname"
exit 1

else

/etc/easy-rsa/easyrsa --batch revoke \$VPNUSER

echo "Updating CRL (Certificate Revocation List)"
/etc/easy-rsa/easyrsa gen-crl

cp \$EASYRSA_DIR/pki/crl.pem \$OPENVPN_DIR/

echo "Restarting VPN service to update CRL"

systemctl restart openvpn@$COMPANY-vpn
echo -e "\e[92m OpenVPN is \$(systemctl is-enabled openvpn@$COMPANY-vpn) and \$(systemctl is-active openvpn@$COMPANY-vpn). \e[0m"

sleep 5

echo "Please ensure user is not connected from the log:"

cat /var/log/openvpn/openvpn-status.log | sed '/ROUTING/q' | head -n -1

fi

EOF

chmod +x /root/revoke_vpn_user

# Configure the Network Stack
cat <<EOF > /etc/sysctl.conf
net.ipv4.ip_forward=1
EOF

# This configures the ip forward for persistence, but we need to set it in the running stack too
sysctl net.ipv4.ip_forward=1

# Fix IP tables
# ip route list # tail -50 /var/log/openvpn/openvpn.log 
iptables -t nat -A POSTROUTING -s 10.8.0.0/16 -o "$NETADAPT" -j MASQUERADE
iptables -t nat -I POSTROUTING -s 10.8.0.0/16 -d 10.0.0.0/16 -o "$NETADAPT" -j MASQUERADE
iptables-save

# Start OpenVPN
systemctl start openvpn@"$COMPANY"-vpn
systemctl enable openvpn@"$COMPANY"-vpn

sleep 2s

# Create user
/root/create_vpn_user "$ADMINUSER"

echo -e "\e[92m OpenVPN is $(systemctl is-enabled openvpn@$COMPANY-vpn) and $(systemctl is-active openvpn@$COMPANY-vpn). \e[0m"
sleep 3s
