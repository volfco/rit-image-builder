#!/bin/bash
# Copyright (c) 2015-2016 VMware, Inc.  All rights reserved.
#
# Description: VMware vRealize Automation and Software Services agents installation script

# Global Constants

[ -z $GUGENT_INSTALL_PATH ] && GUGENT_INSTALL_PATH=/usr/share/gugent
JRE_RELEASE=1.8.0_112
DEFAULT_JAVA=false
DEFAULT_TIMEOUT=300
DEFAULT_CLOUD=vsphere
TEMP_DIR="/tmp/vmAgentInstaller"
SOFTWARE_AGENT_BOOTSTRAP_PATH=/opt/vmware-appdirector/agent-bootstrap
VMWARE_JRE_PATH=/opt/vmware-jre
SOFTWARE_AGENT_DOWNLOAD_PATH=software/download
ARCH64=64
ARCH32=32

CLOUDS="vsphere vca vcd ec2"
RPM_DISTROS="rhel32 rhel64 sles-32 sles-64"
DEB_DISTROS="ubuntu32 ubuntu64"

# Global Variables
vraMajorVersion=7
vRAInstallUnzipDir="VraLinuxGuestAgent"
vRAManagerServiceServer=
vRAManagerServicePort=443
vRAApplianceServer=
vRAAppliancePort=443
arch=
archSoftwareAgentDEB=
archSoftwareAgentRPM=
checkCert=true
cloud=
distro=
interactive=true
fingerprint_appliance=
fingerprint_manager=
java=
timeout=
use_rpm=

cleanTempDir()
{
	rm -rf $TEMP_DIR
}


# Generate Error
Error()
{
	input="$*"

	echo "#######################################################################"
	echo "                           !!! ERROR !!!"
	echo "$input"
	echo "Installation unable to continue!"
	echo "#######################################################################"
}
# Checks to see if a particular command is available on the OS
cmdExist()
{
	input="$*"

	if type "$input" > /dev/null 2>&1
	then
		return 0
	else
		return 1
	fi
}

# Determine if yum exists, this will be used to bootstrap further needed commands
yum=false
apt=false
if cmdExist "yum"; then
	yum=true
elif cmdExist "apt-get"; then
	apt=true;
fi

# Use yum (if available) to install a command if it isn't already available
# Additional arguments are treated as packages to potentially install if
# the command name and the package name do not match.  In time, the querying
# features of yum should be used instead of cmdExist.
installCommand()
{
	for command in $*; do
		if cmdExist $command; then
			return
		fi
	done

	command_alternatives="$*"
	installed_anything=false

	for command in $*; do
		if [ $yum = "true" ]; then
			yum -y install $command
			if [ $? -eq 0 ]; then
				echo "Successfully installed '$command'"
				installed_anything=true
				break
			fi
		elif [ $apt = "true" ]; then
			apt-get -y install $command
			if [ $? -eq 0 ]; then
				echo "Successfully installed '$command'"
				installed_anything=true
				break
			fi
		fi
	done

	if [ $installed_anything = "false" ]; then
		Error "Unable to install possible commands: '$command_alternatives'"
		exit 1
	fi

}

# Usage Output
Usage()
{
	echo
	echo "Installs agents for vRealize Automation and Software Services."
	echo
	echo "Default mode is interactive.  However, all parameters can be passed from"
	echo "the command line with the options listed below."
	echo
	echo "  OPTIONS:"
	echo
	echo "  -m <ManagerServiceHost>  Hostname/IP/VIP of vRealize Manager Service (OPERATIONAL)"
	echo "  -M <ManagerServicePort>  Port of vRealize Manager Service (OPERATIONAL)"
	echo "                           (Operational default to use port $vRAManagerServicePort)"
	echo "  -a <ApplianceServer>     Hostname/IP/VIP of vRealize Appliance (DOWNLOADING)"
	echo "  -A <AppliancePort>       Port of vRealize Appliance (DOWNLOADING)"
	echo "                           (Downloads default to use port $vRAAppliancePort)"
	echo "  -t <seconds>             Timeout for download attempts (Default $DEFAULT_TIMEOUT)"
	echo "  -f <ManagerFingerprint>  Manager Service RSA key fingerprint (OPERATIONAL)"
	echo "  -g <ApplianceFingerprint>vRealize Appliance RSA key fingerprint (DOWNLOADING)"
	echo "  -j <true/false>          Install Java JRE Runtime (Default $DEFAULT_JAVA)"
	echo -n \
	     "  -c                       Cloud Provider (Default $DEFAULT_CLOUD) Valid values are: "
	for item in $CLOUDS; do
		echo -n "'$item', "
	done
	echo
	echo "  -n                       Disable Interactive Mode"
	echo "  -u                       Uninstall gugent/agent from template"
	echo
	echo "Some values are inferred by the OS.  If you'd like to override them use"
	echo "the overrides listed below."
	echo
	echo "  OVERRIDES:"
	echo "  -r <architecture>        Architecture, either '$ARCH64' or '$ARCH32'"
	echo -n \
        "  -l <distro>              Linux distro and version.  Valid values are: "
	for item in $RPM_DISTROS $DEB_DISTROS; do
		echo -n "'$item', "
	done
	echo
}

# Check -s option input
checkCertificate()
{
	input="$*"
	if [[ $input != "true" && $input != "false" ]]; then
		echo "$0: -s: Must be 'true' or 'false'"
		exit 1
	else
		if [[ $input = "true" ]]; then
			checkCert="true"
		else
			checkCert="false"
		fi
	fi
}

# Check -t option input
checkTimeout()
{
	input="$*"

	if expr "$input" : '-\?[0-9]\+$' >/dev/null; then
		timeout=$input
	else
		echo "$0: -t: Must be an integer"
		exit 1
	fi
}

# Check -r option input
checkArch()
{
	input="$*"
	if [[ $input != "$ARCH64" && $input != "$ARCH32" ]]; then
		echo "$0: -s: Must be '$ARCH64' or '$ARCH32'"
		exit 1
	else
		arch=$input
	fi
}

# Check -d option input
checkDistro()
{
	input="$*"

	for match in $RPM_DISTROS; do
		if [ $input = $match ] ; then
			distro=$input
			return 0
		fi
	done

	for match in $DEB_DISTROS; do
		if [[ $input = $match ]] ; then
			distro=$input
			use_rpm="false"
			return 0
		fi
	done

	echo -n "$0: -l: Must be one of the following: "
	for item in $RPM_DISTROS $DEB_DISTROS; do
		echo -n "'$item', "
	done
	echo

	exit 1
}

# Check -c option input
checkCloud()
{
	input="$*"

	for match in $CLOUDS; do
		if [ $input = $match ] ; then
			cloud=$input
			return 0
		fi
	done

	echo -n "$0: Cloud must be one of the following: "
	for item in $CLOUDS; do
		echo -n "'$item', "
	done
	echo

	exit 1
}

# Check -j option input
checkJava()
{
	input="$*"

	if [[ $input != "true" && $input != "false" ]]; then
		echo "$0: -d: Must be 'true' or 'false'"
		exit 1
	else
		java=$input
	fi
}

function calculateFingerprint()
{
    host=$1
    port=$2

    echo QUIT | eval openssl s_client -connect $host:$port 2> /dev/null | sed -ne '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > $TEMP_DIR/cert.pem

    if [ ! -f $TEMP_DIR/cert.pem ]; then
        Error "downloading SSL certificate.  $TEMP_DIR/cert.pem not created."
        exit 1
    fi

    if [ ! -s $TEMP_DIR/cert.pem ]; then
	Error "downloading SSL certificate.  $TEMP_DIR/cert.pem contains nothing."
        exit 1
    fi

    downloaded_fingerprint=$(eval openssl x509 -noout -in $TEMP_DIR/cert.pem -fingerprint -sha1 2> /dev/null | sed -ne 's/\(.*\)=\(.*\)/\2/p')
    if [ -z $downloaded_fingerprint ]; then
        Error "calculating SSL certificate fingerprint"
        exit 1
    fi
    rm $TEMP_DIR/cert.pem

    echo $downloaded_fingerprint
}

function validateCertificateFingerprint() {
    downloaded_fingerprint=$1
    accept_fingerprint=

    while [ -z $accept_fingerprint ]; do
        read input_accept_fingerprint
        if [ -z $input_accept_fingerprint ]; then
            accept_fingerprint="false"
        elif [ $input_accept_fingerprint == "yes" ]; then
            accept_fingerprint="true"
        elif [ $input_accept_fingerprint == "no" ]; then
            accept_fingerprint="false"
        else
            echo -n "Please type 'yes' or 'no': "
        fi
    done

    if [ $accept_fingerprint != "true" ]; then
        return 1
    fi

    return 0
}

removeAgentsRPM()
{

	# Remove gugent (vRA Agent)
	guestAgentRPM=$(rpm -qa | grep 'gugent')

	if [ "$guestAgentRPM" != "" ]; then
		echo "Uninstalling existing vRealize Automation Agent: $guestAgentRPM .. "
		rpm -e $guestAgentRPM
		echo "Deleting /usr/share/gugent dir ..."
		rm -rf /usr/share/gugent
		echo "Deleting /usr/share/log dir ..."
		rm -rf /usr/share/log
		guestAgentRPM=$(rpm -qa | grep 'gugent')
		if [ "$guestAgentRPM" != "" ]; then
			Error "Failed to uninstall $guestAgentRPM"
			exit 1
		else
			echo "vRealize Automation Agent removed successfully!"
		fi
	else
		echo "vRealize Automation Agent not found, skipping uninstall of agent ..."
	fi

	# Remove Software Service Agent
	softwareAgentRPM=$(rpm -qa | grep 'vmware-vra-software-agent')

	if [ "$softwareAgentRPM" != "" ]; then
		echo "Stopping Software Services agent service ..."
		service vmware_vra_software_agent stop
		echo "Uninstalling $softwareAgentRPM ..."
		rpm -e $softwareAgentRPM
		softwareAgentRPM=$(rpm -qa | grep 'vmware-vra-software-agent')
		if [ "$softwareAgentRPM" != "" ]; then
			Error "Failed to uninstall $softwareAgentRPM"
			exit 1
		else
			echo "Software Services Agent removal successfully!"
		fi
	else

		# Remove Old Software Service Agent
		softwareAgentRPM=$(rpm -qa | grep 'vmware-appdirector-agent-service')

		if [ "$softwareAgentRPM" != "" ]; then
			echo "Stopping Software Services agent service ..."
			service vmware_appdirector_agent stop
			echo "Uninstalling $softwareAgentRPM ..."
			rpm -e $softwareAgentRPM
			softwareAgentRPM=$(rpm -qa | grep 'vmware-appdirector-agent-service')
			if [ "$softwareAgentRPM" != "" ]; then
				Error "Failed to uninstall $softwareAgentRPM"
				exit 1
			else
				echo "Software Services Agent removal successfully!"
			fi
		else
			echo "Software Services Agent not found, skipping uninstall of Software Services Agent ..."
		fi
	fi
}

removeAgentsDEB()
{

	guestAgentInstallDEB=$(dpkg-query -W -f '${Package}' gugent)

	if [ "$guestAgentInstallDEB" != "" ]; then
		echo "Uninstalling existing vRealize Automation Agent: $guestAgentInstallDEB .. "
		dpkg -r gugent
		echo "Deleting /usr/share/gugent dir ..."
		rm -rf /usr/share/gugent
		echo "Deleting /usr/share/log dir ..."
		rm -rf /usr/share/log
		guestAgentInstallDEB=$(dpkg-query -W -f '${Package}' gugent)
		if [ "$guestAgentInstallDEB" != "" ]; then
			Error "Failed to uninstall $guestAgentInstallDEB"
		else
			echo "vRealize Automation Agent removed successfully!"
		fi
	else
		echo "vRealize Automation Agent not found, skipping uninstall of agent ..."
	fi

	# Remove Software Service Agent
	# searching by wildcard needs a " " in order to have usable output
	softwareAgentDEB=$(dpkg-query -W -f '${Package} ' vmware-vra-software-agent\*)

	if [ "$softwareAgentDEB" != "" ]; then
		echo "Stopping Software Services agent service ..."
		service vmware_vra_software_agent stop
		echo "Uninstalling $softwareAgentDEB ..."
		dpkg -r $softwareAgentDEB
		if [ $(dpkg-query -W -f '${Package}' $softwareAgentDEB > /dev/null 2>&1) ]; then
			Error "Failed to uninstall $softwareAgentDEB"
			exit 1
		else
			echo "Software Services Agent removal successfully!"
		fi
	else
		echo "Software Services Agent not found, skipping uninstall of Software Services Agent ..."
	fi

}

removeAgents()
{
	echo
	echo "##########################"
	echo "# Remove existing agents #"
	echo "##########################"
	echo

	if [[ $use_rpm = "true" ]]; then
		removeAgentsRPM
	else
		removeAgentsDEB
	fi

	echo
	echo "###############################"
	echo "# Agents Successfully Removed #"
	echo "###############################"
	echo

}

# Parses command line input
while getopts m:M:a:A:c:v:d:t:r:l:j:f:g:s:unh? opt
do
	case $opt in
		m) vRAManagerServiceServer=$OPTARG ;;
		a) vRAApplianceServer=$OPTARG ;;
		M) vRAManagerServicePort=$OPTARG ;;
		A) vRAAppliancePort=$OPTARG ;;
		f) fingerprint_manager=$OPTARG ;;
		g) fingerprint_appliance=$OPTARG ;;
		t) checkTimeout $OPTARG ;;
		r) checkArch $OPTARG ;;
		s) echo Obsolete -s option. Certificates must be verified.; exit 1   ;;
		c) checkCloud $OPTARG ;;
		l) checkDistro $OPTARG ;;
		j) checkJava $OPTARG ;;
		u) removeAgents ; exit 0 ;;
		n) interactive="false" ;;
		h) Usage; exit 0 ;;
		?) Usage; exit 1 ;;
	esac
done

shift $((OPTIND-1))

echo
echo "######################################"
echo "# Cleaning up $TEMP_DIR"
echo "# From any previous installations"
echo "######################################"
echo

cleanTempDir

# Create temp directory
mkdir -p $TEMP_DIR


echo "###################################################"
echo "# Executing a series of 'Pre-flight' checks       #"
echo "# to make sure environment can support the script #"
echo "###################################################"
echo

# List command dependencies here
installCommand "wget" "curl"
installCommand "unzip"
installCommand "sha256sum"
installCommand "grep"
installCommand "sed"
# centos does not have an ifconfig package
installCommand "ifconfig" "net-tools"
# ubuntu does not have chkconfig but plain debian makes it available
if ! cmdExist "upstart-socket-bridge"; then
    installCommand "chkconfig" "sysv-rc-conf"
fi
installCommand "dmidecode"
installCommand "perl"
installCommand "openssl"

echo "###################################################"
echo "# 'Pre-flight' checks complete                    #"
echo "###################################################"
echo

# Begin interactive installer

echo
echo "      ______           _ _                                          ";
echo "      | ___ \         | (_)                                         ";
echo "__   _| |_/ /___  __ _| |_ _______                                  ";
echo "\ \ / /    // _ \/ _\` | | |_  / _ \                                 ";
echo " \ V /| |\ \  __/ (_| | | |/ /  __/                                 ";
echo "  \_/ \_| \_\___|\__,_|_|_/___\___|                                 ";
echo "        ___        _                        _   _                   ";
echo "       / _ \      | |                      | | (_)                  ";
echo "      / /_\ \_   _| |_ ___  _ __ ___   __ _| |_ _  ___  _ __        ";
echo "      |  _  | | | | __/ _ \| '_ \` _ \ / _\` | __| |/ _ \| '_ \       ";
echo "      | | | | |_| | || (_) | | | | | | (_| | |_| | (_) | | | |      ";
echo "      \_| |_/\__,_|\__\___/|_| |_| |_|\__,_|\__|_|\___/|_| |_|      ";
echo "  ___                   _     _____          _        _ _           ";
echo " / _ \                 | |   |_   _|        | |      | | |          ";
echo "/ /_\ \ __ _  ___ _ __ | |_    | | _ __  ___| |_ __ _| | | ___ _ __ ";
echo "|  _  |/ _\` |/ _ \ '_ \| __|   | || '_ \/ __| __/ _\` | | |/ _ \ '__|";
echo "| | | | (_| |  __/ | | | |_   _| || | | \__ \ || (_| | | |  __/ |   ";
echo "\_| |_/\__, |\___|_| |_|\__|  \___/_| |_|___/\__\__,_|_|_|\___|_|   ";
echo "        __/ |                                                       ";
echo "       |___/                                                        ";
echo

if [ -z "$cloud" ]; then
	if [[ $interactive = "true" ]]; then
		echo -n "Cloud Provider: ("
		for item in $CLOUDS; do
			if [ $item = $DEFAULT_CLOUD ]; then
				echo -n "default=$item, "
			else
				echo -n "$item, "
			fi
		done
		echo -n "):"
		read cloud
		if [ -z $cloud ]; then
			cloud=$DEFAULT_CLOUD
		else
			checkCloud $cloud
		fi
	else
		cloud=$DEFAULT_CLOUD
		echo "Using default cloud provider $cloud"
	fi
fi

if [[ -z "$vRAApplianceServer" ]]; then
	if [[ $interactive = "true" ]]; then
		echo "Hostname/IP Address of "
		echo -n "vRealize Appliance: "
		read vRAApplianceServer
	else
		echo "$0: vRealize Appliance must be specified"
		exit 1
	fi
fi

if [[ -z "$vRAManagerServiceServer" ]]; then
	if [[ $interactive = "true" ]]; then
		echo "Hostname/IP Address of "
		echo -n "Manager Service Server: "
		read vRAManagerServiceServer
	else
		echo "$0: Manager Service Server must be specified"
		exit 1
	fi
fi

downloaded_fingerprint=$(calculateFingerprint $vRAManagerServiceServer $vRAManagerServicePort)
if [ -z "$fingerprint_manager" -a "$downloaded_fingerprint" ]; then
	echo "Manager Service RSA key fingerprint is $downloaded_fingerprint."
	if [ $interactive = "true" ]; then
		echo -n "Do you accept this for the Manager Service (yes/no)? "
		validateCertificateFingerprint $downloaded_fingerprint
		if [ $? -ne -0 ]; then
			echo "$0: Manager Service RSA key verification fingerprint is not accepted."
			exit 1
		else
			fingerprint_manager=$downloaded_fingerprint
		fi
	elif [ $checkCert != "true" ]; then
		fingerprint_manager=$downloaded_fingerprint
	else
		echo "$0: Manager Service RSA key verification fingerprint must be specified."
		exit 1
	fi
elif [ $fingerprint_manager != $downloaded_fingerprint -o -z $downloaded_fingerprint ]; then
	echo "$0 Manager Service RSA key fingerprint $downloaded_fingerprint does not match verification $fingerprint_manager"
	exit 1
fi

downloaded_fingerprint=$(calculateFingerprint $vRAApplianceServer $vRAAppliancePort)
if [ -z "$fingerprint_appliance" -a "$downloaded_fingerprint" ]; then
	echo "vRealize Appliance RSA key fingerprint is $downloaded_fingerprint."
	if [ $interactive = "true" ]; then
		echo -n "Do you accept this for the vRealize Appliance (yes/no)? "
		validateCertificateFingerprint $downloaded_fingerprint
		if [ $? -ne -0 ]; then
			echo "$0: vRealize Appliance RSA key verification fingerprint is not accepted."
			exit 1
		else
			fingerprint_appliance=$downloaded_fingerprint
		fi
	elif [ $checkCert != "true" ]; then
		fingerprint_appliance=$downloaded_fingerprint
	else
		echo "$0: vRealize Appliance RSA key verification fingerprint must be specified."
		exit 1
	fi
elif [ $fingerprint_appliance != $downloaded_fingerprint -o -z $downloaded_fingerprint ]; then
	echo "$0 vRealize Appliance RSA key fingerprint $downloaded_fingerprint does not match verification $fingerprint_appliance"
	exit 1
fi

checkCertificate false

# Ask about timeout
if [[ -z "$timeout" ]]; then
	if [[ $interactive = "true" ]]; then
		echo -n "Set download timeout (in seconds) for download [$DEFAULT_TIMEOUT]:"
		read newtimeout
		if [ ! -z $newtimeout ]; then
			timeout=$newtimeout
		else
			timeout=$DEFAULT_TIMEOUT
		fi
	else
		timeout=$DEFAULT_TIMEOUT
	fi
fi

# Ask about java
if [[ -z "$java" ]]; then
	if [[ $interactive = "true" ]]; then
		echo -n "Download and install Java Runtime Environment $JRE_RELEASE? [y\N]:"
		read installJava
		if [[ $installJava != "Y" && $installJava != "y" ]]; then
			java="false"
		else
			java="true"
		fi
	else
		java=$DEFAULT_JAVA
	fi
fi

echo
echo "############################"
echo "# Determining Architecture #"
echo "############################"
echo

if [[ -z $arch ]]; then
	if [ $(uname -m | grep '64') ]; then
		echo "Architecture: 64-bit";
		arch="$ARCH64";
	else
		echo "Architecture: 32-bit"
		arch="$ARCH32"
	fi
fi

if [ $arch == $ARCH64 ]; then
	archSoftwareAgentDEB=amd64
	archSoftwareAgentRPM=x86_64
else
	archSoftwareAgentDEB=i386
	archSoftwareAgentRPM=i386
fi

echo
echo "###############################################"
echo "# Determining Linux Distro and version number #"
echo "###############################################"
echo

if [[ -z $distro ]]; then
	if [ -f /etc/debian_version ] ; then
# Ubuntu records the code name in /etc/debian_version from which Ubuntu was forked
# where a plain debian distribution will store the debian version number.
		if [[ $(grep '^[0-9].' /etc/debian_version) ]] ; then
			Error "Detected an unsupported version of a Debian distribution"
			exit 1
		elif [[ $(grep "DISTRIB_ID=Ubuntu" /etc/lsb-release)   ]] ; then
			echo "Distro is Ubuntu"
			if [[ $(grep "DISTRIB_RELEASE=14\.04" /etc/lsb-release) ]] ; then
				distro="ubuntu$arch"
			elif [[ $(grep "DISTRIB_RELEASE=14\.10" /etc/lsb-release) ]] ; then
				distro="ubuntu$arch"
			else
				Error "Detected an unsupported version of an Ubuntu distribution"
				exit 1
			fi
			distro="ubuntu$arch"
		else
			Error "Detected an unsupported version of a Debian distribution"
			exit 1
		fi
		use_rpm=false
	elif [[ $(cat /etc/*release | grep -i centos) ]] || [[ $(cat /etc/*release | grep -i rhel) ]] \
		|| [[ $(cat /etc/*release | grep -i "red hat") ]]; then
		echo "Distro is RHEL/CentOS"
		if [[ $(cat /etc/*release | grep -i "release 7") ]]; then
			distro="rhel$arch"
		elif [[ $(cat /etc/*release | grep -i "release 6") ]]; then
			distro="rhel$arch"
		elif [[ $(cat /etc/*release | grep -i "release 5") ]]; then
			distro="rhel$arch"
		else
			Error "Detected an unsupported version of Redhat/CentOS"
			exit 1
		fi
		use_rpm=true
	elif [[ $(cat /etc/*release | grep -i suse) ]]; then
		if [[ ($(cat /etc/*release | grep -i "11")) ]]; then
			distro="sles$arch"
		elif [[ ($(cat /etc/*release | grep -i "12")) ]]; then
			distro="sles$arch"
		else
			Error "Detected an unsupported version of SUSE"
			exit 1
		fi
		use_rpm=true
	else
		Error "Unable to detect host operating system. Please specify override (Use '-?' option for more info)"
		exit 1
	fi
fi

echo "This distro is detected to have closest compatibility with: $distro";

echo " _____        _    _    _                       ";
echo "/  ___|      | |  | |  (_)                    _ ";
echo "\ \`--.   ___ | |_ | |_  _  _ __    __ _  ___ (_)";
echo " \`--. \ / _ \| __|| __|| || '_ \  / _\` |/ __|   ";
echo "/\__/ /|  __/| |_ | |_ | || | | || (_| |\__ \ _ ";
echo "\____/  \___| \__| \__||_||_| |_| \__, ||___/(_)";
echo "                                   __/ |        ";
echo "                                  |___/         ";
echo "################################################################################"
echo "# Here are the current settings:"
echo "#"
echo "# vRealize Appliance Server IP:             $vRAApplianceServer"
echo "# Manager Service Server IP:                $vRAManagerServiceServer"
echo "# Cloud provider:                           $cloud"
echo "# Check Certificates:                       $checkCert"
echo "# Download timeout:                         $timeout"
echo "# Architecture:                             $arch"
echo "# Linux Distro*:                            $distro"
echo "# Install Java $JRE_RELEASE:                   $java"
echo "# * This may be an approximation (e.g. CentOS/Redhat both show up as 'RHEL')"
echo "################################################################################"

if [[ $interactive = "true" ]]; then
	echo -n "Would you like to start the installation? [Y/n]:"
	read cont

	if [[ $cont != "N" && $cont != "n" ]]; then
		echo "Starting Installation..."
	else
		echo "Cancelling Installation"
		exit 0;
	fi
fi

wgetOptions="--timeout $timeout"
curlOptions="--connect-timeout $timeout"
if [[ $checkCert != "true" ]]; then
	if cmdExist "wget"; then
		wgetOptions="--no-check-certificate $wgetOptions"
	else
		curlOptions="-k $curlOptions"
	fi
fi

# Install Java
InstallJava()
{
	echo
	echo "######################################"
	echo "# Installing Java JRE $JRE_RELEASE      #"
	echo "######################################"
	echo

	if [[ $arch = "$ARCH64" ]]; then
		javaZip="jre-$JRE_RELEASE-lin64.zip"
	else
		javaZip="jre-$JRE_RELEASE-lin32.zip"
	fi

	echo "Downloading $javaZip file from https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH .. "
	if cmdExist "wget"; then
		wget $wgetOptions -O $TEMP_DIR/$javaZip https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$javaZip
	else
		curl $curlOptions -o $TEMP_DIR/$javaZip https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$javaZip
	fi

	if [ $? -ne 0 ]; then
		Error "Unable to download file https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$javaZip"
		exit 1
	else
		echo "Successfully downloaded https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$javaZip"
	fi

	echo "Cleaning out old java from $VMWARE_JRE_PATH ..."
	rm -rf $VMWARE_JRE_PATH

	echo "Unzipping Java Zip to $TEMP_DIR ..."
	unzip -q -o $TEMP_DIR/$javaZip -d $VMWARE_JRE_PATH

	if [ $? -ne 0 ]; then
		Error "Unable to extract $javaZip"
		exit 1
	else
		echo "Successfully extracted $javaZip into $VMWARE_JRE_PATH"
	fi

	if [[ $($VMWARE_JRE_PATH/bin/java -version 2>&1 | grep "version \"$JRE_RELEASE") ]]; then
		echo "Java installed successfully in $VMWARE_JRE_PATH"
	else
		Error "Java install failed: $JRE_RELEASE"
		exit 1
	fi

}

# Install JRE if required
if [[ $java = "true" ]]; then
	InstallJava
fi

# Remove Agents
removeAgents

DebInstallGuestAgent()
{
	GuestAgentDEBName="gugent_$vraMajorVersion*.deb"

	echo "Installing vRealize Automation Guest Agent DEB"

	# 'LinuxGuestAgentPkgs' directory may or may not be extracted due to vRA change
	if [ ! -d "$TEMP_DIR/$vRAInstallUnzipDir" ]; then
		echo "dpkg -i $TEMP_DIR/$distro/$GuestAgentDEBName"
		dpkg -i $TEMP_DIR/$distro/$GuestAgentDEBName
	else
		echo "dpkg -i $TEMP_DIR/$vRAInstallUnzipDir/$distro/$GuestAgentDEBName"
		dpkg -i $TEMP_DIR/$vRAInstallUnzipDir/$distro/$GuestAgentDEBName
	fi

	GuestAgentInstallDEB=$(dpkg-query -W -f '${Package}' gugent)

	if [ "$GuestAgentInstallDEB" != "" ]; then
		echo "vRealize Automation Guest Agent installed successfully!"
	else
		Error "Unable to install vRealize Automation Guest Agent"
		exit 1
	fi


}

RpmInstallGuestAgent()
{
	GuestAgentRPMName="gugent-$vraMajorVersion*.*.rpm"

	echo "Installing vRealize Automation Guest Agent RPM"

	# 'LinuxGuestAgentPkgs' directory may or may not be extracted due to vRA change
	if [ ! -d "$TEMP_DIR/$vRAInstallUnzipDir" ]; then
		echo "rpm -i $TEMP_DIR/$distro/$GuestAgentRPMName"
		rpm -i $TEMP_DIR/$distro/$GuestAgentRPMName
	else
		echo "rpm -i $TEMP_DIR/$vRAInstallUnzipDir/$distro/$GuestAgentRPMName"
		rpm -i $TEMP_DIR/$vRAInstallUnzipDir/$distro/$GuestAgentRPMName
	fi

	GuestAgentInstallRPM=$(rpm -qa | grep 'gugent')

	if [ "$GuestAgentInstallRPM" != "" ]; then
		echo "vRealize Automation Guest Agent installed successfully!"
	else
		Error "Unable to install vRealize Automation Guest Agent"
		exit 1
	fi
}

InstallGuestAgent()
{
	GuestAgentInstallZip="LinuxGuestAgentPkgs.zip"

	echo
	echo "##############################################"
	echo "# Install vRealize Automation Guest Agent    #"
	echo "##############################################"
	echo

	echo "Downloading vRealize Automation Guest Agent archive from https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH .. "

	if cmdExist "wget"; then
		wget $wgetOptions -O $TEMP_DIR/$GuestAgentInstallZip https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$GuestAgentInstallZip
	else
		curl $curlOptions -o $TEMP_DIR/$GuestAgentInstallZip https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$GuestAgentInstallZip
	fi

	if [ $? -ne 0 ]; then
		Error "Failed to download file: https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$GuestAgentInstallZip"
		exit 1
	else
		echo "Successfully downloaded https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$GuestAgentInstallZip"
	fi

	echo "Unzipping vRealize Automation Guest Agent archive to $TEMP_DIR ..."
	unzip -o $TEMP_DIR/$GuestAgentInstallZip -d $TEMP_DIR/

	if [ $? -ne 0 ]; then
		Error "Unable to extract $GuestAgentInstallZip"
		exit 1
	else
		echo "Successfully extracted $GuestAgentInstallZip"
	fi

	if [[ $use_rpm = "true" ]]; then
		RpmInstallGuestAgent
	else
		DebInstallGuestAgent
	fi

}

InstallGuestAgent

DebInstallSoftwareAgent()
{
	package_file_name=$1

	# Install DEB and confirm
	echo "Installing Software Services Agent DEB"
	echo "dpkg -i $TEMP_DIR/$package_file_name"
	dpkg -i $TEMP_DIR/$package_file_name

	registered_package_name=$(dpkg-query -W -f '${Package}' vmware-vra-software-agent\*)

	if [ "$registered_package_name" != "" ]; then
		echo "Software Services Agent installed successfully!"
	else
		Error "Unable to install Software Services Agent"
		exit 1
	fi

}

RpmInstallSoftwareAgent()
{
	package_file_name=$1

	# Install RPM and confirm
	echo "Installing Software Services Agent RPM"
	echo "rpm -i $TEMP_DIR/$package_file_name"
	rpm -i $TEMP_DIR/$package_file_name

	registered_package_name=$(rpm -qa | grep 'vmware-vra-software-agent')

	if [ "$registered_package_name" != "" ]; then
		echo "Software Services Agent installed successfully!"
	else
		Error "Unable to install Software Services Agent"
		exit 1
	fi
}

InstallSoftwareAgent()
{
	echo
	echo "######################################"
	echo "# Install Software Services Agent    #"
	echo "######################################"
	echo

	if [[ $use_rpm = "true" ]]; then
		package_file_name="vmware-vra-software-agent-service_7.2.0.0-0_$archSoftwareAgentRPM.rpm"
	else
		package_file_name="vmware-vra-software-agent-service_7.2.0.0-0_$archSoftwareAgentDEB.deb"
	fi

	echo "Downloading Software Agent package from https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH .. "

	if cmdExist "wget"; then
		wget $wgetOptions -O $TEMP_DIR/$package_file_name https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$package_file_name
	else
		curl $curlOptions -o $TEMP_DIR/$package_file_name https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$package_file_name
	fi

	if [ $? -ne 0 ]; then
		Error "Unable to download file https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$package_file_name"
		exit 1
	else
		echo "Successfully downloaded https://$vRAApplianceServer:$vRAAppliancePort/$SOFTWARE_AGENT_DOWNLOAD_PATH/$package_file_name"
	fi

	if [[ $use_rpm = "true" ]]; then
		RpmInstallSoftwareAgent $package_file_name
	else
		DebInstallSoftwareAgent $package_file_name
	fi

	echo
	echo "##################################################"
	echo "# Resetting Software Service Agent Bootstrap     #"
	echo "##################################################"
	echo

	echo "$SOFTWARE_AGENT_BOOTSTRAP_PATH/agent_reset.sh"
	$SOFTWARE_AGENT_BOOTSTRAP_PATH/agent_reset.sh
}

InstallSoftwareAgent

echo
echo "##########################################################################"
echo "# Registering vRealize Automation Agent with Manager Service Server      #"
echo "##########################################################################"
echo

echo "$SOFTWARE_AGENT_BOOTSTRAP_PATH/vra_register.sh -m $vRAManagerServiceServer -M $vRAManagerServicePort -c $cloud -f $fingerprint_manager";
$SOFTWARE_AGENT_BOOTSTRAP_PATH/vra_register.sh -m $vRAManagerServiceServer -M $vRAManagerServicePort -c $cloud -f $fingerprint_manager

if [ $? -ne 0 ]; then
	Error "Unable to register vRealize Automation Agent to Manager Service Server"
	exit 1
else
	echo "Successfully registered vRealize Automation Agent to Manager Service Server"
fi


echo
echo "######################################"
echo "# Checking that Service is Installed #"
echo "######################################"
echo

# The various linux distributions fall into general categories of how the
# startup scripts are managed and used.  Therefore the existence of the
# following commands on Linux are about conformance to standardization
# for the distribution.  It just so happens the output of chkconfig and
# sysv-rc-conf are compatible for our needs.

if cmdExist "upstart-socket-bridge"; then

	status vrm-agent
	if [ $? -eq 0 ]; then
		echo "vrm-agent service is installed"
	else
		Error "vrm-agent may not be configured correctly"
		exit 1
	fi

elif cmdExist "chkconfig"; then

# chkconfig is sensitive to the locale for string matching purposes

	isInstalled=$(LANGUAGE=en chkconfig --list | grep vrm-agent)
	isInstalledWithLanguage=$(chkconfig --list | grep vrm-agent)
	if [[ $isInstalled =~ .*vrm-agent.*0:(off).*1:(off).*2:(off).*3:(on).*4:(off).*5:(on).*6:(off).* ]]; then
		echo "vrm-agent service is installed: $isInstalledWithLanguage"
	else
		Error "vrm-agent may not be configured correctly: $isInstalledWithLanguage"
		exit 1
	fi

else

	isInstalled=$(LANGUAGE=en sysv-rc-conf --list | grep vrm-agent)
	isInstalledWithLanguage=$(sysv-rc-conf --list | grep vrm-agent)
	if [[ $isInstalled =~ .*vrm-agent.*0:(off).*1:(off).*2:(off).*3:(on).*4:(off).*5:(on).*6:(off).* ]]; then
		echo "vrm-agent service is installed: $isInstalledWithLanguage"
	else
		Error "vrm-agent may not be configured correctly: $isInstalledWithLanguage"
		exit 1
	fi
fi

echo
echo "######################################"
echo "# Cleaning up $TEMP_DIR"
echo "######################################"
echo

cleanTempDir

echo
echo "#######################################"
echo "# Installation Completed Successfully #"
echo "# Ready to capture as a template      #"
echo "#######################################"
echo
