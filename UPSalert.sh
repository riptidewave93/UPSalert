#!/bin/bash 

# UPSalert - Used to Monitor APC UPS Battery Unit vi SNMP, and bring systems offline/online based on power status
# By Chris Blake
# http://servernetworktech.com
# Version 3.00

# Required Packages
# snmp (for snmpget)
# ping
# ipmitool
# bsd-mailx (for mailx)

# Required Setup
# SSH setup with public/private keys to the storage hosts and servers, as well has host keys already remembered.

# Install Instructions
# 1. Install required packages listed above
# 2. Setup ssh with public keys on all systems
# 3. Move this script to /opt/upsalert/
# 4. add a cronjob to run this script as root

# Alert Email Settings
SENDEMAIL=1 # Set to 1 to enable, 0 to disable
MAILTO="mail@user.com"

# APC UPS SNMP Settings
IP="10.1.1.55"
SNMPVER="2c"
COMMUNITY="Community"

# At what point should the script shutdown servers?
# Ex 0500 = 5 minutes, MUST USE 0000 format.
ShutdownTime='0500'

# Define the Storage Hosts here
StorageHost[0]='10.1.8.2'

# Define the shutdown command for the Storage Hosts.
StorageHostShutdown[0]='halt'

# Define the startup command for the Storage Hosts
# Make into array to have multiple startup commands
StorageHostStart[0]='wakeonlan -i 10.1.7.22 00:11:22:33:44:55'

# Define the Server IP's here
VMHost[0]='10.1.6.2'
VMHost[1]='10.1.6.3'
VMHost[2]='10.1.6.4'
VMHost[3]='10.1.6.5'

# Define the Shutdown commands for the servers
VMHostShutdown[0]='halt'
VMHostShutdown[1]='/mnt/stuff/scripts/Shutdown.sh'
VMHostShutdown[2]='halt'
VMHostShutdown[3]='halt'

# Define the startup command for the servers
# Make into array to have multiple startup commands
VMHostStart[0]='ipmitool -I lanplus -H 10.1.7.18 -U user -P pass power on'
VMHostStart[1]='wakeonlan -i 10.1.7.16 00:11:22:33:44:55'
VMHostStart[2]='ipmitool -I lanplus -H 10.1.7.19 -U user -P pass power on'
VMHostStart[3]='ipmitool -I lan -H 10.1.7.20 -U user -P pass power on'

##########################################################################
# Code starts here, no need to edit after this                           #
##########################################################################

# Define ALL the Functions
# Used to print debug messages
DebugPrint() {
if [ "$DebugEnabled" = 'true' ]
then    
    echo "DEBUG: $1"
fi
}
# Used to Start a host. Takes in host and start CMD, returns status
StartHost() {
	ReturnCode=1
    DebugPrint "StartHost() Called, var $1"
	if [ -z "$1" ] 
	then
		DebugPrint "StartHost() Error: \$1 not defined for StopHost()"
	else
		DebugPrint "StartHost() Running Start Command:"
		TempCMD=$(${@:1})
		ReturnCode=$?
		DebugPrint "StartHost() Ran, Response: $TempCMD ResponseCode: $ReturnCode"
	fi
	return $ReturnCode
}
# Used to Stop a host. Takes in host and stop CMD, returns status
StopHost() {
    DebugPrint "StopHost() Called, vars $1, ${@:2}"
	if [ -z "$1" ] 
	then
		DebugPrint "StopHost() Error: \$1 not defined for StopHost()"
	elif [ -z "$2" ]
	then
		DebugPrint "StopHost() Error: \$2 not defined for StopHost()"
		return 1
	elif [ "$1" ] && [ "$2" ]
	then
		if ssh -q root@$1 exit
		then
			DebugPrint "StopHost() Successfully connected to $1! Continuing..."
			ShutdownCode=$(ssh root@$1 ${@:2})
			DebugPrint "StopHost() System $1 CMD result: $ShutdownCode"
			return 0
		else
			DebugMessage="StopHost() Unable to SSH into System $1, Check your Host Keys."
			DebugPrint "$DebugMessage"
			return 1
		fi
	else
		DebugPrint "StopHost() Error: args not defined for StopHost()"
		return 1
	fi
}
# Used to create/remove/check pid file
PIDFile(){
    DebugPrint "PIDFile() Called, var $1"
    if [ "$1" = 'check' ]
    then
        if [ -a /var/run/UPSalert.pid ]
        then
            return 0
        else
            return 1
        fi
    elif [ "$1" = 'create' ]
    then
        if [ -a /var/run/UPSalert.pid ]
        then
            DebugPrint "PIDFile() Error: PID File Already Exists, Erroring!"
            return 1
        else
            DebugPrint "PIDFile() Creating PID File with PID $$"
            echo $$ > /var/run/UPSalert.pid
            return 0
        fi
    elif [ "$1" = 'remove' ]
    then
        rm /var/run/UPSalert.pid
        DebugPrint "PIDFile() Removed PID File /var/run/UPSalert.pid"
        return 0
    else
        DebugPrint "PIDFile() Error: Invalid PIDFile() Command Recieved!"
        return 1
    fi
}
# Used to check/create/remove shutdown file from running dir
ShutdownFile(){
    DebugPrint "ShutdownFile() Called, var $1"
    if [ "$1" = "check" ]
    then
        if [ -a "$pwd/.shutdown" ]
        then
			DebugPrint "ShutdownFile() .shutdown file found"
            return 1
        else
			DebugPrint "ShutdownFile() .shutdown file not found"
			return 0
        fi
    elif [ "$1" = "create" ]
    then
        if [ -e "$pwd/.shutdown" ]
        then
            DebugPrint "ShutdownFile() Error: .shutdown File Already Exists, Erroring!"
            return 1
        else
            DebugPrint "ShutdownFile() Creating .shutdown file"
            touch "$pwd/.shutdown" 
            return 0
        fi
    elif [ "$1" = "remove" ]
    then
        if [ -e "$pwd/.shutdown" ]
        then
            DebugPrint "ShutdownFile() Removing .shutdown file"
            rm "$pwd/.shutdown" 
            return 0
        else
            DebugPrint "ShutdownFile() Error: .shutdown File Does Not Exist, Erroring!"
            return 1
        fi        
    else
        DebugPrint "ShutdownFile() Error: Unknown arg in ShutdownFile(), Erroring!"
        return 1
    fi
}
# Used to print help information
PrintHelp(){
    echo -e "UPSAlert V3.0 - By Chris Blake (chrisblake93@gmail.com)"
    echo -e "http://ServerNetworkTech.com/ \n\nUsage: \n -h     Help Page\n -v     Verbose Debug Mode"
}
# Used to exit a script, and take care of cleanup
ScriptExit() {
    DebugPrint "ScriptExit() called, var $1"
    RetCode=1 # By default, error
    if [ "$1" = 'normal' ]
    then
        RetCode=0 # Don't error, we were killed properly
    elif [ "$1" = 'errorpid' ]
    then
        DebugPrint "ScriptExit() Exiting with Error and keeping PID File"
        exit $RetCode
    elif [ "$1" = 'error' ]
    then
        DebugPrint "ScriptExit() Exiting with Error, Removing PID File"
    elif [ "$1" ]
    then
        DebugPrint "ScriptExit() Unknown ScriptExit arg of $1, Exiting Anyways!"    
    else
        DebugPrint "ScriptExit() Unknown ScriptExit call without arg, Exiting Anyways!"
    fi
    # PID Check?
    if PIDFile check
    then
        DebugPrint "ScriptExit() PID File does exist, removing!"
        PIDFile remove
    else
        DebugPrint "ScriptExit() PID File does not exist, no need to remove"    
    fi    
    exit $RetCode
}
# Used to send email messages about the status of everything
SendEmail(){
    DebugPrint "SendEmail() called, var $1"
    ReturnCode=0
    EmailSubjectHeader="UPSalert:"
	if [ "$SENDEMAIL" -eq "1" ]
	then
		case $1 in
			1)
				# Power Loss
				echo "Hello, This message is to inform you that your servers are now on UPS power. If power is not restored before the threshold, your servers will be shutdown." | mailx -s "$EmailSubjectHeader Power Loss, on UPS Power" $MAILTO
				;;        
			2)
				# Power Was Lost, but Restored Before Shutdown
				echo "Hello, This message is to inform you that power was restored before the shutdown threshold was reached. Your systems will not shutdown, and operations are back to normal." | mailx -s "$EmailSubjectHeader Power Restored before Shutdown Threshold" $MAILTO		
				;;        
			3)
				# Power Was Lost, Nodes are Being Shutdown
				echo "Hello, This message is to inform you that your UPS is running critically low, and your systems are now shutting down. They will be turned back on once power is restored." | mailx -s "$EmailSubjectHeader Power Critical, Systems Shutting Down" $MAILTO		
				;;
			4)
				# Power Was Restored, Servers are being brought back online
				echo "Hello, This message is to inform you that your power has been restored and your systems are being booted." | mailx -s "$EmailSubjectHeader Power Restored, Starting Systems" $MAILTO
				;;
			5)
				# Power was Restored, Servers are back online
				echo "Hello, This message is to inform you that your servers are now back online as power was restored." | mailx -s "$EmailSubjectHeader Power Restored, Systems Online" $MAILTO
				;;
			6)
				# Script Error
				echo -e "Hello, This message is to inform you that UPSalert has had a critical error, and is prematurely terminating. Please Review your logs, if any, to figure out the cause of this. \n\nDebug Message: $DebugMessage" | mailx -s "$EmailSubjectHeader Critical Script Error" $MAILTO
				;;
			7)
				# Power Was Lost, Systems are Offline
				echo - "Hello, This message is to inform you that your systems are now offline. They will be restarted once power has been restored to your UPS." | mailx -s "$EmailSubjectHeader Power Critical, Systems Offline" $MAILTO
				;;
			*)
				# Unknown/Error
				DebugPrint "SendEmail() Unknown var $1, Erroring"
				ReturnCode=1
				;;
		esac
	else
		DebugPrint "SendEmail() Sending of Email is Disabled! Ignoring"
	fi
    return $ReturnCode
}
# Used to ping the status of a host to see if it is online or offline
PingCheck() {
    DebugPrint "PingCheck() called, var $1"
	if [ "$1" ]
	then
		PINGCHECK=$(ping -c 1 $1 | grep 'received' | awk -F',' '{ print $2 }' | awk '{ print $1 }')
		if [ "$PINGCHECK" -eq "0" ];
			then
				DebugPrint "PingCheck() Node $1 Confirmed Offline"
				return 0
			else
				DebugPrint "PingCheck() Node $1 is Pingable"
				return 1
			fi
	else
		DebugPrint "PingCheck() Error: \$1 was not defined in PingCheck(), Erroring"
		return 1
	fi
}

##### Start Actual Script #####

# Check for args
if [ "$1" = '-h' ]
then
    PrintHelp
    exit 0
elif [ "$1" = '-v' ]
then
    DebugEnabled='true'
    DebugPrint "Verbose Mode Enabled!"
elif [ "$1" ]
then
    echo -e "Error, Invalid Flag!"
    PrintHelp
fi
# Start Debug output early
DebugPrint "Starting Script"
# Are we root?
if [ "$(id -u)" != "0" ]
then
    DebugPrint "Error: This script must be ran as root!"
    ScriptExit error
fi
# Are we running? check vi pid
if PIDFile check
then
    DebugPrint "PIDFile Already Exists, Are we Running? Exiting"
    ScriptExit errorpid
fi
# Make PID file, did we error?
if PIDFile create
then
    DebugPrint "PIDFile Create Ran Successfully!"
else
    DebugPrint "PIDFile Create Failed, Exiting!"
    ScriptExit errorpid
fi
# Define Debug Message, only used when we REALLY break and is sent over email
DebugMessage="Sorry, I have nothing :/"
# Define SNMP OIDs here, only change if you know what you are doing!
UPSSTATUSOID=".1.3.6.1.4.1.318.1.1.1.4.1.1.0"
UPSRUNTIMEOID=".1.3.6.1.4.1.318.1.1.1.2.2.3.0"
# Define call code for later use
CALLCODE="/usr/bin/snmpget -Oqv -c $COMMUNITY -v $SNMPVER $IP"
# define our first call, used to make sure we are on battery
UPSSTATUS=$($CALLCODE $UPSSTATUSOID) # returns a number between 0-12, each is a UPS state.
# Define the host values here so the loop doesn't repeat this code
NumOfVMHosts=${#VMHost[@]}
NumOfStorageHosts=${#StorageHost[@]}
HostCounter=0 # Start at 0, we count up to NumOfVMHosts, then count back to 0 when doing shutdown check
# Loop vars, used to keep loops going
Loop=0
HostCount=0
PingLoopCount=0
# Debug all the things
DebugPrint "VMHostCount=$NumOfVMHosts, StorageHostCount=$NumOfStorageHosts"
# Check UPS Status, if we have one
if [ -z "$UPSSTATUS" ]
then
    DebugPrint "Error: UPS Call Error! \$UPSSTATUS is null. Exiting!"
    ScriptExit error
elif [ "$UPSSTATUS" -eq "2" ] || [ "$UPSSTATUS" -eq "4" ]
then
    DebugPrint "UPS is not on battery and is online."
    # Do we need to bring things back?
    if ShutdownFile check
    then
        DebugPrint "No Shutdown File found. Terminating Script Normally"
    else
        DebugPrint "Shutdown File Exists! Starting Recovery"
		SendEmail 4
		# Bring up Storage Hosts first
		let HostCount=0
		while [ "$HostCount" -ne "$NumOfStorageHosts" ]
		do
			if StartHost ${StorageHostStart[$HostCount]}
			then
				DebugPrint "StartHost() Ran successfully for ${StorageHost[$HostCount]}, moving on..."
			else
				DebugPrint "StartHost() Had an error on ${StorageHost[$HostCount]}! Terminating with fatal error!"
				SendEmail 6
				ScriptExit error
			fi
			let HostCount=$HostCount+1
		done
		DebugPrint "Done with Storage Node CMD Bringup!"
		# Now we ping to make sure storage is live
		let HostCount=0
		let PingLoopCount=0
		while [ "$HostCount" -ne "$NumOfStorageHosts" ]
		do
			if [ "$PingLoopCount" -eq '20' ]
			then
				DebugPrint "Storage ${StorageHost[$HostCount]} failed to come online after 20 checks!"
				DebugMessage="Storage ${StorageHost[$HostCount]} failed to come online after 20 ping checks, script will now terminate."
				SendEmail 6
				ScriptExit error
			fi
			if PingCheck ${StorageHost[$HostCount]}
			then
				DebugPrint "Node ${StorageHost[$HostCount]} is still offline. Pausing 2 seconds"
				let PingLoopCount=$PingLoopCount+1
				sleep 2
			else
				DebugPrint "Node ${StorageHost[$HostCount]} is Online! Continuing..."
				let HostCount=$HostCount+1
			fi
		done
		# NAS is Online, we can now bring up the nodes
		let HostCount=0
		while [ "$HostCount" -ne "$NumOfVMHosts" ]
		do
			if StartHost ${VMHostStart[$HostCount]}
			then
				DebugPrint "StartHost() Ran successfully for ${VMHost[$HostCount]}, moving on..."
			else
				DebugPrint "StartHost() Had an error on ${VMHost[$HostCount]}! Terminating with fatal error!"
				SendEmail 6
				ScriptExit error
			fi
			let HostCount=$HostCount+1
		done
		DebugPrint "Done with VM Node CMD Bringup!"			
		# Ping Check the nodes to make sure they are back online
		let HostCount=0
		let PingLoopCount=0
		while [ "$HostCount" -ne "$NumOfVMHosts" ]
		do
			if [ "$PingLoopCount" -eq '20' ]
			then
				DebugPrint "Node ${VMHost[$HostCount]} failed to come online after 20 checks!"
				DebugMessage="Node ${VMHost[$HostCount]} failed to come online after 20 ping checks, script will now terminate."
				SendEmail 6
				ScriptExit error
			fi
			if PingCheck ${VMHost[$HostCount]}
			then
				DebugPrint "Node ${VMHost[$HostCount]} is still offline. Pausing 2 seconds"
				let PingLoopCount=$PingLoopCount+1
				sleep 2
			else
				DebugPrint "Node ${VMHost[$HostCount]} is Online! Continuing..."
				let HostCount=$HostCount+1
			fi
		done		
		# Things are live, remove offline file and send email
		if ShutdownFile remove
		then
			DebugPrint "Shutdown File removed successfully, sending email now that we are recovered"
			SendEmail 5
		else
			DebugPrint "Failed to Remove Shutdown File! Erroring out and terminating"
			DebugMessage="The script was unable to remove the offline file even though all of your systems seem to be back online."
			SendEmail 6
			ScriptExit error
		fi
    fi
elif [ "$UPSSTATUS" -eq "3" ]
then
	DebugPrint "We are on battery, Starting Check Loop"
    SendEmail 1
    while [ "$Loop" -eq "0" ]
    do
        let UPSSTATUS=$($CALLCODE $UPSSTATUSOID) # Recalculate status code every loop
        # Are we off battery?
		if [ "$UPSSTATUS" -eq "2" ] || [ "$UPSSTATUS" -eq "4" ]
		then
			DebugPrint "UPS is no longer on battery, leaving check mode"
            SendEmail 2
            let Loop=1
			break
        fi
		#Are we already offline?
		if ShutdownFile check
		then
			DebugPrint "No Shutdown File Found, Continuing"
		else
			DebugPrint "Shutdown File Found, we are already offline!"
			let Loop=1
			break
		fi
		#Are we within the shutdown threshold?
		if [ $($CALLCODE $UPSRUNTIMEOID | awk -F':' '{print $3$4}' | awk -F'.' '{print $1}' ) -le "$ShutdownTime" ]
		then
			DebugPrint "UPS is within Critical Range, Shutting down nodes"
			SendEmail 3
			# Start with VM Nodes
			let HostCount=0
			while [ "$HostCount" -ne "$NumOfVMHosts" ]
			do
				if StopHost ${VMHost[$HostCount]} ${VMHostShutdown[$HostCount]}
				then
					DebugPrint "StopHost() Ran successfully for ${VMHost[$HostCount]}, moving on..."
				else
					DebugPrint "StopHost() Had an error on ${VMHost[$HostCount]}! Terminating with fatal error!"
					SendEmail 6
					ScriptExit error
				fi
				let HostCount=$HostCount+1
			done
			DebugPrint "Done with VM Node Shutdown!"
			# Ping Check to make sure each is dead
			let HostCount=0
			let PingLoopCount=0
			while [ "$HostCount" -ne "$NumOfVMHosts" ]
			do
				if PingCheck ${VMHost[$HostCount]} 
				then
					DebugPrint "Node ${VMHost[$HostCount]} is Now Offline"
					let HostCount=$HostCount+1
					let PingLoopCount=0
				else
					DebugPrint "Node ${VMHost[$HostCount]} is still alive. Pausing 2 seconds"
					let PingLoopCount=$PingLoopCount+1
					sleep 2
				fi
				if [ "$PingLoopCount" -eq '20' ]
				then
					DebugPrint "Node ${VMHost[$HostCount]} failed to shutdown after 20 checks!"
					DebugMessage="Node ${VMHost[$HostCount]} failed to shutdown after 20 ping checks. script will sleep for 60 seconds then continue on."
					SendEmail 6
					sleep 60
					let HostCount=$HostCount+1
					let PingLoopCount=0
				fi
			done
			DebugPrint "All Nodes are Fully Offline, Moving to Storage"
			# Finish with Storage Nodes
			let HostCount=0
			while [ "$HostCount" -ne "$NumOfStorageHosts" ]
			do
				if StopHost ${StorageHost[$HostCount]} ${StorageHostShutdown[$HostCount]}
				then
					DebugPrint "StopHost() Ran successfully for ${StorageHost[$HostCount]}, moving on..."
				else
					DebugPrint "StopHost() Had an error on ${StorageHost[$HostCount]}! Terminating with fatal error!"
					SendEmail 6
				fi
				let HostCount=$HostCount+1
			done
			DebugPrint "Done with Storage Shutdown!"
			# One more Ping Check
			let HostCount=0
			let PingLoopCount=0
			while [ "$HostCount" -ne "$NumOfStorageHosts" ]
			do
				if PingCheck ${StorageHost[$HostCount]}
				then
					DebugPrint "Node ${StorageHost[$HostCount]} is Now Offline"
					let HostCount=$HostCount+1
				else
					DebugPrint "Node ${StorageHost[$HostCount]} is still alive. Pausing 2 seconds"
					let PingLoopCount=$PingLoopCount+1
					sleep 2
				fi
				if [ "$PingLoopCount" -eq '20' ]
				then
					DebugPrint "Storage ${StorageHost[$HostCount]} failed to shutdown after 20 checks!"
					DebugMessage="Storage ${StorageHost[$HostCount]} failed to shutdown after 20 ping checks. script will sleep for 60 seconds then continue on."
					SendEmail 6
					sleep 60
					let HostCount=$HostCount+1
					let PingLoopCount=0
				fi
			done
			DebugPrint "All Storage Servers are Fully Offline, Shutdown Process Complete"
			#Create Shutdown File
			if ShutdownFile create
			then
				DebugPrint "Shutdown File Created Successfully"
				SendEmail 7
			else
				DebugPrint "Shutdown File Failed to create. Oh god, what did you do to get here?! Exiting with error email as we are in a CRITICAL state!"
				DebugMessage="Failed to Create Shutdown File, Possible Permission issue or script location issue. We do not like running in folders with spaces in the name FYI."
				SendEmail 6
				ScriptExit error
			fi
		else
			DebugPrint "We are not within the shutdown range, sleeping for 5 seconds"
			sleep 5
		fi
    let Loop=1 # Change loopvar to break out
    done
else
    DebugPrint "Unknown \$UPSSTATUS of $UPSSTATUS"
    DebugPrint "APC Code Lookup at http://bit.ly/1l8Yebv"
    ScriptExit error
fi
DebugPrint "Script Finished!"
ScriptExit normal
