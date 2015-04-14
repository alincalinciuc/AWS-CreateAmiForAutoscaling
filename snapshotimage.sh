#!/bin/bash

# Instance settings
instanceId="i-f9a2f62e"
imageDescription="sefaira.com-production"
today=`date +"%M-%H-%d-%b-%Y"`
logfile="/var/log/aws-autoscaling-image-update.log"
noReboot=1
imageName="$imageDescription-$today"

# AutoScaling group settings
sshKey="sefaira_web"
securityGroups="webserver Access"
instanceType="m3.medium"
launchConfigurationName="sefairaCom-$today"
spotPriceEnabled=0
spotPrice="0.50"

# Launch configuration settings
autoScalingGroupName="SefairaAutoscaling"

# How many days do you wish to retain backups for? Default: 7 days
retention_days="7"
retention_date_in_seconds=`date +%s --date "$retention_days days ago"`

# Start log file: today's date
echo $today >> $logfile

# Create image from running instance
if [ "$noReboot" = 1 ]; then
	amiImage=$(aws ec2 create-image --output=text --instance-id $instanceId --no-reboot --name $imageName --description $imageDescription --query ImageId)
else
	amiImage=$(aws ec2 create-image --output=text --instance-id $instanceId --reboot --name $imageName --description $imageDescription --query ImageId)
fi
echo "AMI image $amiImage is being created." >> $logfile

# Wait for the image to be available
imageState=$(aws ec2 describe-images --filters Name=name,Values=$imageName --query Images[].State --output text)
timeWaited=0
while [ "$imageState" = "pending" ]; do
        if [ $timeWaited -ge 300 ]; then
		echo "Image was not successful created after 5 mins" >> $logfile
                exit 1
        fi
        sleep 30
        timeWaited=$[$timeWaited+30]
	imageState=$(aws ec2 describe-images --filters Name=name,Values=$imageName --query Images[].State --output text)
        echo "Waiting for image to be available $timeWaited" >> $logfile
done
echo "Image was built successfuly after $timeWaited seconds." >> $logfile

# Create a new launch configuration with the new image
if [ "$spotPriceEnabled" = 1 ]; then
	autoScalingLaunchConfiguration=$(aws autoscaling create-launch-configuration --launch-configuration-name $launchConfigurationName --instance-type $instanceType --spot-price $spotPrice --security-groups $securityGroups --image-id $amiImage --key $sshKey --instance-monitoring '{"Enabled":0}')
	echo "Launch configuration $launchConfigurationName with AMI $amiImage, instance type $instanceType and spot price $spotPrice has been created." >> $logfile
else
	autoScalingLaunchConfiguration=$(aws autoscaling create-launch-configuration --launch-configuration-name $launchConfigurationName --instance-type $instanceType --security-groups $securityGroups --image-id $amiImage --key $sshKey --instance-monitoring '{"Enabled":0}')
	echo "Launch configuration $launchConfigurationName with AMI $amiImage, instance type $instanceType has been created." >> $logfile
fi

# Update autoscaling group with the latest launch configuration
autoScaling=$(aws autoscaling update-auto-scaling-group --auto-scaling-group-name $autoScalingGroupName --launch-configuration-name $launchConfigurationName)
echo "Autoscaling group $autoScalingGroupName has been updated." >> $logfile
