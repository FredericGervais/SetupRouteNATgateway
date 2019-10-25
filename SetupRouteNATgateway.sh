# Name: SetupRouteNATgateway.sh
# Author: Frederic Gervais
#


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


read -p "Please select the REGION in which to create the NAT instances [0-$i]:" selection </dev/tty

if  [[ $selection -lt 0 ]] || [[ $selection -gt $i ]]; then
  echo "Error, the number $selection is not between 0 and $i"
fi


#
# Get the zones of the region
#
declare -a ZonesOfRegion
ZonesOfRegion=($(gcloud compute zones list --filter="REGION:(${regions[$selection]})" --format="value(name)"))
echo ${ZonesOfRegion[*]}

read -p "Press [Enter] key to start backup..."

