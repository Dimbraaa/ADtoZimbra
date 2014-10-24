#!/bin/bash

## AD to ZIMBRA Account Provisioning and Synchronization
## 
## Tested with :
## Red Hat Enterprise Linux Server release 6.4 
## ZCS Release 8.0.5 NETWORK edition
## GNU bash, version 4.1.2(1)-release (x86_64-redhat-linux-gnu)
## 
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.

####################################################################
## Variables
####################################################################

## PATH
## full /path/to/script (path -p for symlinks)
RUNPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
## Or :
#RUNPATH=/dir/you/can/write/to
#RUNPATH=`pwd`

####### ACTIVE DIRECTORY #######
# Active Directory domain name
AD_domain="domain.local"

# Domain controller ip address
AD_ip="10.10.10.10"

# Distinguished name of AD OU to look in
AD_basedn="CN=Users,DC=domain,DC=local"

# AD user fqdn and password we use to connect to AD. Regular domain user is enough
AD_fqdn_user="CN=ADuser,OU=Users,DC=domain,DC=local"
AD_password="P4ssword"

####### LDAP ATTRIBUTES #######

## LDAP attributes to filter on
# AD_attribute_filter : "givenName sn sAMAccountName" are mandatory
AD_attribute_filter="givenName sn telephoneNumber company department postalCode l co sAMAccountName"
# ZCS_attribute_filter : "givenName sn" are mandatory
ZCS_attribute_filter="givenName sn telephoneNumber company title postalCode l co"
					
####### ZIMBRA #######
# ZCS mail domain name
ZCS_domain="domain.tld"

# ZCS_cos : COS to search for accounts to match. Can be empty (= search all COSes)
ZCS_cos="default"

# Default ZCS password for newly created accounts (used as a fallback if external authentication is on, but fails)
ZCS_default_password="H4rd_P4ssword"

# List Zimbra user id that will never be processed. Multiple uid are separated by a blank e.g. "test test1". Can be empty.
ZCS_user_exclusion_list="test test1"

# Signature name used when creating account signature. Can be empty if you dont want to create signature
ZCS_signature_name="default_signature"

## HTML Signature (needed if ZCS_signature_name is exists)
# In this example signature, sig_givenName, sig_sn et sig_telephoneNumber will be replaced by user values of $ZCS_givenName, $ZCS_sn and $ZCS_telephoneNumber
ZCS_signature_html="<div><span style='Modern; font-size: 10pt'>sig_givenName sig_sn<br>Téléphone : sig_telephoneNumber<br><a href='http://www.website.tld' title='Our Website' target='_blank'>www.domain.tld</a></span></div>"

######################################################################
## Temp files

tmp_AD_mail_list=$RUNPATH/tmp_AD_mail_list.txt
tmp_ZCS_mail_list=$RUNPATH/tmp_ZCS_mail_list.txt
tmp_DELTA_mail_list=$RUNPATH/tmp_DELTA_mail_list.txt
tmp_USER_attributes=$RUNPATH/tmp_USER_attributes.txt
tmp_COMMON_mail_list=$RUNPATH/tmp_COMMON_mail_list.txt
tmp_AD_attributes=$RUNPATH/tmp_AD_attributes.txt
tmp_ZCS_attributes=$RUNPATH/tmp_ZCS_attributes.txt
tmp_ZCS_database=$RUNPATH/tmp_ZCS_database.txt
tmp_AD_to_ZCS_attributes=$RUNPATH/tmp_AD_to_ZCS_attributes.txt
tmp_zmprov_cmd=$RUNPATH/tmp_zmprov_cmd.txt
tmp_ZCS_attribute_filter=$RUNPATH/tmp_ZCS_attribute_filter.txt
error_log=$RUNPATH/error_log.txt


######################################################################
## FUNCTION : usage
## Displays script's usage
usage () {
	echo ""
	echo "Usage :"
	echo "$0 -h"
	echo "$0 [ -d ] TEST|RUN"
	echo ""
	echo "-h         This help message"
	echo "-d         Activates script debug mode"
	echo ""
	echo "TEST    -- don't run core commands (e.g. accounts modifications...)"
	echo "RUN     -- run all commands. "
	echo ""
	echo "For your safety, execute \"$0 TEST\" first and check tmp files in $RUNPATH"
	echo ""
	exit
}

######################################################################
## FUNCTION : cleanup
## delete temporary files
cleanup () {
	rm -f $RUNPATH/tmp_*
}

######################################################################
## FUNCTION : flush_stdin
## flushes stdin (e.g. before a read command)
flush_stdin () {
	read -t 1 -n 10000 discard 
}

######################################################################
## FUNCTION : get_AD_mail
## Builds list of users with an email address filled in AD
## - Attribute "mail" value must contain $ZCS_domain
## - AD account must an activated user (see userAccountControl)
get_AD_mail () {
	ldapsearch -LLL -x -H ldap://"$AD_ip" -b "$AD_basedn" -D "$AD_fqdn_user" -w "$AD_password" "(&(mail=*@"$ZCS_domain")(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))" mail \
	| grep mail: | awk '{print $2}' | cut -d "@" -f1 | tr '[:upper:]' '[:lower:]' | sort -fn
}

######################################################################
## FUNCTION : get_AD_userattributes
## Builds list of attributes of an AD user. Attributes are filtered by $AD_attribute_filter
## Argument $1 : user
get_AD_userattributes () {
	ldapsearch -LLL -x -H ldap://"$AD_ip" -b "$AD_basedn" -D "$AD_fqdn_user" -w "$AD_password" "(&(mail=$1@$ZCS_domain)(objectClass=user))" $AD_attribute_filter | sort -fn
}

######################################################################
## FUNCTION : get_ZCS_COS_mail
## Builds list of accounts for a given COS : $ZCS_cos_zimbraId
get_ZCS_COS_mail () {
	if [[ x$ZCS_cos != "x" ]] ## TODO : verify if COS exists with zmprov getAllCos
	then
		ZCS_cos_zimbraId=$(zmprov gc $ZCS_cos zimbraId | grep zimbraId: | awk '{print $2}')
		zmprov -l getAllAccounts -v $ZCS_domain \
		| egrep -e uid: -e zimbraCOSId: | egrep -B1 $ZCS_cos_zimbraId | egrep uid: | awk '{print $2}' | sort -fn
	else
		zmprov -l getAllAccounts -v $ZCS_domain \
		| cut -d "@" -f1 | sort -fn
	fi
}


######################################################################
## MAIN

## Shell must be bash
if [ "x$BASH" = "x" ]; then
	echo ""
	echo "The shell interpreter used to run this script is not bash."
	echo "This script is to be run by bash."
	echo "Please execute it either as "
	echo ""
	echo "bash ./ad_sync.sh [arguments]"
	echo ""
	echo "or"
	echo ""
	echo "./ad_sync.sh [arguments]"
	echo ""
	exit 1
fi

## We must be able to write to $RUNPATH
if [ ! -w $RUNPATH ]; then echo "Error : can't write to $RUNPATH" ; exit 1; fi

## We must run script as zimbra user
if [[ $USER != "zimbra" ]]; then echo "Error : this script must be run as zimbra user" ; exit 1 ; fi 

##	Processing parameters
while [ $# -ne 0 ]; do
	case $1 in
	-h|-help|--help)
		usage
		exit 0
		break
		;;
    -d|--debug)
		## Print commands and their arguments as they are executed.
		set -x
		## Print shell input lines as they are read.
		#set -v
		## Exit immediately if a command exits with a non-zero status.
		#set -e
		;;
    RUN)
		## Set RUN=true to really execute core commands (e.g. zmprov createAccount)
		RUNMODE=RUN
		RUN=true
		break
		;;
	TEST)
		## Set RUN=false to NOT execute core commands
		RUNMODE=TEST
		RUN=false
		break
		;;
	*) 
		echo "Error : incorrect parameter"
		usage
		exit 1
		;;
	esac
	shift
done

## Exit if too much parameters
if [ $# -gt 1 ]; then
	echo "Error : too much parameters"
	echo "See \"$0 --help\" for more informations"
	exit 1
fi

## Exit if missing parameter
if [ x$RUN == "x" ]; then
	echo "Error : missing parameter. A run mode must be given : TEST or RUN"
	echo "See \"$0 --help\" for more informations"
	exit 1
fi

clear
echo ""
echo ".-------------------------------------------------------------------."
echo "|        AD to ZIMBRA Account Provisioning and Synchronization      |"
echo "'-------------------------------------------------------------------'"
echo ""
echo "    You can modify parameters inside the script."
echo "    Sync is unidirectional : AD will not be modified"
echo "    Zimbra accounts are created like this : givenName.sn@domain.tld"
echo "    with an alias sAMAccountName@domain.tld"
echo ""
echo "    Be careful : AD is not case sensitive, but Zimbra is !"
echo ""
echo "                       Run Mode = $RUNMODE"
echo ""
echo " ---------------------------- MENU ---------------------------------"
echo ""

## MENU SELECT
PS3="
Enter your choice: "
options=("Help" "Create accounts" "Synchronize attributes" "Quit")
select opt in "${options[@]}"
do 
	case "$REPLY" in
	
	1)
		usage
		;;
	2)
		echo -e "\nEnumerating AD and ZCS users..."
		
		cleanup
		get_AD_mail > $tmp_AD_mail_list
				
		if [[ x$ZCS_cos != "x" ]] ## TODO : verify if COS exists with zmprov gac
		then
			ZCS_cos_zimbraId=$(zmprov gc $ZCS_cos zimbraId | grep zimbraId: | awk '{print $2}')
			zmprov -l getAllAccounts -v $ZCS_domain \
			| egrep -e uid: -e zimbraCOSId: | egrep -B1 $ZCS_cos_zimbraId | egrep uid: | awk '{print $2}' | sort -fn > $tmp_ZCS_mail_list
		else
			zmprov -l getAllAccounts -v $ZCS_domain \
			| cut -d "@" -f1 | sort -fn > $tmp_ZCS_mail_list
		fi

		
		## Builds list of users with an email existing in AD, and not in Zimbra
		## /!\ input lists must be sorted for comm
		comm -13 $tmp_ZCS_mail_list $tmp_AD_mail_list > $tmp_DELTA_mail_list
		
		## remove users from $ZCS_user_exclusion_list
		for user in $ZCS_user_exclusion_list 
		do
			sed -i -e "/$user/d" $tmp_DELTA_mail_list
		done
			
		
		if [[ -s $tmp_DELTA_mail_list ]]
		then
			echo -e "\nThose addresses don't exist in domain $ZCS_domain :"
			cat $tmp_DELTA_mail_list
			echo ""
			
			for usermail in $(cat $tmp_DELTA_mail_list)
			do
				flush_stdin
				read -r -p "Do you want to create account $usermail ? [o/N] " answer
				if [[ ! $answer =~ ^([oO])$ ]]
				then
					## remove user from file
					sed -i -e "/\<$usermail\>/d" $tmp_DELTA_mail_list
				fi
			done
			
			echo ""
			
			if [[ -s $tmp_DELTA_mail_list ]]
			then
				echo "Those accounts will be created :"
				cat $tmp_DELTA_mail_list
				
				for usermail in $(cat $tmp_DELTA_mail_list)
				do
					## Get AD attibutes
					get_AD_userattributes $usermail | egrep -v "dn:" > $tmp_USER_attributes
					
					## Set ZCS attributes values from AD values. Case modified when i need / prefer to. Your choice.
					ZCS_givenName=$(cat $tmp_USER_attributes | egrep givenName: | awk '{print $2}')
					ZCS_sn=$(cat $tmp_USER_attributes | egrep sn: | awk '{print $2}')
					ZCS_telephoneNumber=$(cat $tmp_USER_attributes | egrep telephoneNumber: | awk '{print $2}')
					ZCS_company=$(cat $tmp_USER_attributes | egrep company: | awk '{print $2}')
					ZCS_title=$(cat $tmp_USER_attributes | egrep department: | awk '{print $2}' | tr '[:lower:]' '[:upper:]')
					ZCS_l=$(cat $tmp_USER_attributes | egrep l: | awk '{print $2}')
					ZCS_postalCode=$(cat $tmp_USER_attributes | egrep postalCode: | awk '{print $2}')
					ZCS_co=$(cat $tmp_USER_attributes | egrep co: | awk '{print $2}')
				
					## Formatting email address (givenName.sn@domain.tld)
					ZCS_mail=$(echo $ZCS_givenName.$ZCS_sn@$ZCS_domain | tr '[:upper:]' '[:lower:]')
					
					## Formatting alias (sAMAccountName@domain.tld)
					ZCS_alias="$(cat $tmp_USER_attributes | egrep sAMAccountName: | awk '{print $2}' | tr '[:upper:]' '[:lower:]')@$ZCS_domain"
					
					echo -e "\n\nCreating account $usermail@$ZCS_domain" 
					echo "Attributes to put in Zimbra LDAP:"
					cat $tmp_USER_attributes | grep -v "sAMAccountName:"
										
					## Creating account	if RUN=true			
					$RUN && \
					zmprov createAccount $ZCS_mail $ZCS_default_password displayName ''$ZCS_givenName' '$ZCS_sn'' \
					zimbraCOSid "$ZCS_cos_zimbraId" \
					givenName "$ZCS_givenName" \
					sn "$ZCS_sn" \
					telephoneNumber "$ZCS_telephoneNumber" \
					company "$ZCS_company" \
					title "$ZCS_title" \
					l "$ZCS_l" \
					postalCode "$ZCS_postalCode" \
					co "$ZCS_co" \
					>/dev/null 2>>$error_log \
					&& echo -e "\n--> $ZCS_mail account created successfully!"
					
					## Creating alias if RUN=true
					echo -en "\nCreating alias : $ZCS_alias..."
					$RUN && zmprov addAccountAlias $ZCS_mail $ZCS_alias && echo " OK !"
					
					## Creating search folders if RUN=true #TODO : parametrizing + test
					echo -ne "Creating search folders..."
					$RUN && zmprov selectMailbox $ZCS_mail createSearchFolder -t message "/Big mails received" "larger:3MB has:attachment NOT in:sent" >/dev/null 2>>$error_log && echo -ne " OK !"
					$RUN && zmprov selectMailbox $ZCS_mail createSearchFolder -t message "/Big mails sent" "larger:3MB has:attachment in:sent" >/dev/null 2>>$error_log && echo -e "... OK !"
					
					## Creating default signature if RUN=true and $ZCS_signature_html exists
					## We build a zmprov command file
					if [[ x$ZCS_signature_html != "x" ]]
					then
						echo -n "csig $ZCS_mail $ZCS_signature_name zimbraPrefMailSignatureHTML " > $tmp_zmprov_cmd
						echo -n \""$ZCS_signature_html"\" >> $tmp_zmprov_cmd
					
						## We replace sig_givenName sig_sn sig_telephoneNumber with corresponding values
						sed -i -e "s/sig_givenName/$ZCS_givenName/" $tmp_zmprov_cmd
						sed -i -e "s/sig_sn/$ZCS_sn/" $tmp_zmprov_cmd
						sed -i -e "s/sig_telephoneNumberNumber/$ZCS_telephoneNumber/" $tmp_zmprov_cmd

						echo -en "Creating signature..."

						$RUN && zmprov -f $tmp_zmprov_cmd >/dev/null 2>>$error_log \
						&& echo " OK !"
					fi
					
					## TODO : Injecting welcome mail with zmlmtpinject

				done
				
			else
				echo "Nothing to create !"
			fi			
		
		else
			echo -e "\n--> CONFORMITY OK"
			echo -e "\n\tAll emails found in AD's @$ZCS_domain domain exist in Zimbra specified COS"
			echo -e "\tOU base search DN : $AD_basedn"
			echo -e "\tZimbra COS : $ZCS_cos"
			echo ""
		fi
		
		
		$RUN && cleanup
		echo -e "\nReturn to menu...(press enter to display it)"
		echo -e "\n-------------------------- MENU -------------------------------"
		;;

	3)
		echo -e "\nEnumerating AD and ZCS users..."
		
		#cleanup
		cleanup
		get_AD_mail > $tmp_AD_mail_list
		
		## Get all ZCS accounts and attributes (can be long)
		zmprov -l getAllAccounts -v $ZCS_domain > $tmp_ZCS_database		
		
		if [[ x$ZCS_cos != "x" ]] ## TODO : vérify if COS exists with zmprov getAllCos
		then
			ZCS_cos_zimbraId=$(zmprov gc $ZCS_cos zimbraId | grep zimbraId: | awk '{print $2}')
			egrep -e uid: -e zimbraCOSId: $tmp_ZCS_database | egrep -B1 $ZCS_cos_zimbraId | egrep uid: | awk '{print $2}' | sort -fn > $tmp_ZCS_mail_list
		else
			egrep uid: $tmp_ZCS_database | cut -d "@" -f1 | sort -fn > $tmp_ZCS_mail_list
		fi		
		
		## return common user id between AD and ZCS
		## /!\ comm needs sorted input
		comm -12 $tmp_ZCS_mail_list $tmp_AD_mail_list > $tmp_COMMON_mail_list
		
		if [[ -s $tmp_COMMON_mail_list ]]
		then
	
			## Construct attributes filters to pass to grep
			for attribute in $ZCS_attribute_filter; do echo "^$attribute:" >> $tmp_ZCS_attribute_filter; done
			
			## Add account delimiter : each account returned by 'zmprov getAllAccounts' begins with "# name".
			## Also contains the user id that we'll need later
			echo "^# name" >> $tmp_ZCS_attribute_filter
			
			## Keep only filtered lines
			grep -f $tmp_ZCS_attribute_filter $tmp_ZCS_database > $tmp_ZCS_database.tmp
			
			## Awk processing. Records from zmprov getAllAccounts (and from $tmp_ZCS_database) are delimited by # and fields by \n
			## We rebuild output on a single line by account. $1=$1 permits to reevaluate defaut delimiter which is " ", when printing $0
			## Then we cut to remove " name"
			awk 'BEGIN { RS = "#" ; FS = "\n" }; { $1=$1 ; print $0 }' $tmp_ZCS_database.tmp \
			| cut -d " " -f 3- \
			> $tmp_ZCS_database
			
			for usermail in $(cat $tmp_COMMON_mail_list)
			do
				
				rm -f $tmp_AD_to_ZCS_attributes 
				
				echo -e "\nProcessing user $usermail ..."
				
				## Get and format AD attributes file for $usermail
				## We use sed to replace AD "department" attribute name, because we want ZCS "title" to match AD "department" attribute
				get_AD_userattributes $usermail | grep -v "dn:" | grep -v -e '^$' | sed 's/department/title/g' | sort -fn > $tmp_AD_attributes
					
				## Get and format ZCS attributes file for $usermail
				grep $usermail $tmp_ZCS_database | cut -d " " -f 2- | awk '{ for (i=1; i<=NF; i=i+2) print $i,$(i+1)}' | sort -fn > $tmp_ZCS_attributes

				## Check if some attributes are different
				if [[ `comm -13 $tmp_ZCS_attributes $tmp_AD_attributes` ]]
				then
					## Let's compare attributes names then values
					for attribute in $(cat $tmp_AD_attributes | awk '{print $1}')
					do
						AD_attribute=$(cat $tmp_AD_attributes | grep $attribute | awk '{print $2}')
						ZCS_attribute=$(cat $tmp_ZCS_attributes | grep $attribute | awk '{print $2}')
						ZCS_attribute_filtered=$(echo "$ZCS_attribute_filter " | sed -e "s/ /: /g" )
						
						## Check if attribute is filtered on, and if value differs
						if [[ $ZCS_attribute_filtered =~ $attribute && $AD_attribute != $ZCS_attribute ]] 
						then 
							echo -e "\tAttribute \"$attribute\" value in ZCS ($ZCS_attribute) is different from AD ($AD_attribute)."
							echo -en "\t"
							flush_stdin
							read -n 1 -r -p "Do you want to replace ZCS attribute value ? [o/N] " answer
							if [[ $answer =~ ^([oO])$ ]]
							then
								echo -ne "$attribute $AD_attribute " >> $tmp_AD_to_ZCS_attributes
								echo -e "\n\t--> OK"
							else 
								echo -e "\n\t--> Value kept"
							fi
						fi
						
						if [[ -s $tmp_AD_to_ZCS_attributes ]]
						then
							## Formatting
							sed -i 's/://' $tmp_AD_to_ZCS_attributes
						fi
						
					done
					if [[ -s $tmp_AD_to_ZCS_attributes ]]
					then
						echo -n "modifyAccount $usermail@$ZCS_domain " >> $tmp_zmprov_cmd
						echo $(cat $tmp_AD_to_ZCS_attributes) >> $tmp_zmprov_cmd
					else
						echo -e "\t--> OK"
					fi
				fi

			done
			
			## ZCS core command for synchronizing
			if [[ -s $tmp_zmprov_cmd ]]
				then
					$RUN && \
					zmprov -f $tmp_zmprov_cmd >/dev/null 2>>$error_log && \
					echo -e "\n Synchronization is successful !"
					echo ""
				else
					echo ""
					echo "---------------------------------------------------"
					echo "--> Already synchronized, or no changes to make <--"
					echo "---------------------------------------------------"
			fi
		
		else
			echo -e "\n--> No common email accounts between AD and Zimbra specified COS"
			echo -e "\tOU base search DN : $AD_basedn"
			echo -e "\tZimbra COS : $ZCS_cos"
		fi
		
		echo -e "\nReturn to menu...(press enter to display it)"
		echo -e "\n-------------------------- MENU -------------------------------"
		
		$RUN && cleanup
		;;

	4)
		echo ""
		echo "Goodbye !"
		exit 0
		;;
	esac
done
exit 0
