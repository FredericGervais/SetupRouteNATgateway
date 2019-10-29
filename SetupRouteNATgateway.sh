# Name: SetupRouteNATgateway.sh
# Author: Frederic Gervais
#

NatTag=no-ip

#
# Select the region
#
echo Here are the available regions:
regions=($(gcloud compute regions list --format="value(name)"))
i=-1
for OUTPUT in ${regions[*]}
do
  i=$(($i + 1))
  echo [$i] $OUTPUT
done


read -p "Please select the REGION in which to create the NAT instances [0-$i]:" selection
echo "Welcome $selection!"

if  [[ $selection -lt 0 ]] || [[ $selection -gt $i ]]; then
  echo "Error, the number $selection is not between 0 and $i"
fi


#
# Get the zones of the region
#
declare -a ZonesOfRegion
ZonesOfRegion=($(gcloud compute zones list --filter="REGION:(${regions[$selection]})" --format="value(name)"))
echo ${ZonesOfRegion[*]}


echo Getting the NAT instance startup script ...
gsutil cp gs://nat-gw-template/startup.sh .

echo Creating Health Check ...
gcloud compute health-checks create http nat-health-check --check-interval 30 --healthy-threshold 1 --unhealthy-threshold 5 --request-path /health-check --no-user-output-enabled

echo Adding firewall rule to allow Health Checks ...
gcloud compute firewall-rules create "natfirewall" --allow tcp:80 --target-tags natgw --source-ranges "130.211.0.0/22","35.191.0.0/16" --no-user-output-enabled

i=1
while [ $i -le ${#ZonesOfRegion[@]} ]; do

  echo Configuring nat-$i

  echo -n [+] Creating a Public IP : 
  gcloud compute addresses create nat-$i --region ${regions[$selection]} --no-user-output-enabled

  PublicIP=$(gcloud compute addresses describe nat-$i --region ${regions[$selection]} --format='value(address)')
  echo " $PublicIP"

  echo [+] Creating Instance Template
  gcloud compute instance-templates create nat-$i --machine-type n1-standard-2 --can-ip-forward --tags natgw --metadata-from-file=startup-script=startup.sh --address $PublicIP --no-user-output-enabled

  echo [+] Creating Instance Group in Zone : ${ZonesOfRegion[$(($i - 1))]}
  gcloud compute instance-groups managed create nat-$i --size=1 --template=nat-$i --zone=${ZonesOfRegion[$(($i - 1))]} --no-user-output-enabled

  echo [+] Setup the Autoscaling
  gcloud compute instance-groups managed update nat-$i --health-check nat-health-check --initial-delay 120 --zone=${ZonesOfRegion[$(($i - 1))]} --no-user-output-enabled

  echo [+] Add a Route
  NatInstanceName=$(gcloud compute instances list | grep -P nat-$i | awk '{print $1}')
  gcloud compute routes create natroute$i --destination-range 0.0.0.0/0 --tags $NatTag --priority 800 --next-hop-instance-zone=${ZonesOfRegion[$(($i - 1))]} --next-hop-instance=$NatInstanceName --no-user-output-enabled

  i=$(($i + 1))
done

echo Adding Google SPF to the $NatTag tag so you can SSH to the natted instances

SPFlist=$(nslookup -q=TXT _spf.google.com 8.8.8.8  | grep -oP '_netblocks(\d+|).google.com')
SPFip=$(for OUTPUT in ${SPFlist};do nslookup -q=TXT $OUTPUT 8.8.8.8;done;)
SPFip=$(echo ${SPFip} | grep -oP '\d+.\d+.\d+.\d+/\d+' | sort -V)

i=0
for OUTPUT in ${SPFip}
do
  echo Creating route for $OUTPUT
  gcloud beta compute routes create nat-to-google-$i --network=default --priority=750 --tags=$NatTag --destination-range=$OUTPUT --next-hop-gateway=default-internet-gateway --no-user-output-enabled
  i=$(($i + 1))
done

echo The script has completed
