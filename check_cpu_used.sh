#!/bin/bash
#
# Check CPU Performance plugin for Nagios
#
# Licence : GPL - http://www.fsf.org/licenses/gpl.txt
#
# Initial Author : Luke Harris
# Adaptations by : tstrike, Etienne Magro
# version       : 20220920
# Creation date : 1 October 2010
# Revision date : 20 Sep 2022
# Description   : Nagios plugin to check CPU performance statistics.
#               This script has been tested on the following Linux and Unix platforms:
#		RHEL 4, RHEL 5, RHEL 6, CentOS 4, CentOS 5, CentOS 6, SUSE, Ubuntu, Debian, FreeBSD 7, AIX 5, AIX 6, and Solaris 8 (Solaris 9 & 10 *should* work too)
#               The script is used to obtain key CPU performance statistics by executing the sar command, eg. user, system, iowait, steal, nice, idle
#		The Nagios Threshold test is based on CPU idle percentage only, this is NOT CPU used.
#               EDIT : Values have been inverted for legacy monitoring system rules integration
#               EDIT : So if (100-CPUidle)>warning) => raises warning alert
#               EDIT : and if (100-CPUidle)>critical) => raises critical alert
#		Support has been added for Nagios Plugin Performance Data for integration with Splunk, NagiosGrapher, PNP4Nagios,
#		opcp, NagioStat, PerfParse, fifo-rrd, rrd-graph, etc
#
# USAGE         : ./check_cpu_perf.sh {warning} {critical} {iowait_warning} {iowait_critical}
#
# Example: ./check_cpu_perf.sh 80 90 5 15
# OK: CPU Idle = 84.10% | CpuUser=12.99; CpuNice=0.00; CpuSystem=2.90; CpuIowait=0.01; CpuSteal=0.00; CpuIdle=84.10:20:10
#
# Note: the option exists to NOT test for a threshold. Specifying 0 (zero) for both warning and critical will always return an exit code of 0.

WARNING=${1:-0}
CRITICAL=${2:-0}
IOWAIT_WARNING=${3:-0}
IOWAIT_CRITICAL=${4:-0}

#Ensure warning and critical limits are passed as command-line arguments
if [ -z "$1" -o -z "$2" ]
then
 echo "Please include at least two arguments, eg."
 echo "Usage: $0 {warning} {critical} [{iowait_warning} {iowait_critical}]"
 echo "Example :-"
 echo "$0 80 90"
exit 3
fi

#Disable nagios alerts if warning and critical limits are both set to 0 (zero)
if [ $WARNING -eq 0 -a $CRITICAL -eq 0 ]
  then
    ALERT=false
fi

#Disable nagios alerts if iowait_warning and iowait_critical limits are both set to 0 (zero)
if [ $IOWAIT_WARNING -eq 0 -a $IOWAIT_CRITICAL -eq 0 ]
  then
    IOWAIT_ALERT=false
fi

#Ensure warning is greater than critical limit
if [ $CRITICAL -lt $WARNING ]
 then
  echo "Please ensure critical threshold is greater than warning threshold, eg."
  echo "Usage: $0 80 90"
  exit 3
fi

#Ensure iowait_warning is greater than iowait_critical limit
if [ $IOWAIT_CRITICAL -lt $IOWAIT_WARNING ]
 then
  echo "Please ensure iowait_critical threshold is greater than iowait_warning threshold, eg."
  echo "Usage: $0 80 90 5 15"
  exit 3
fi

SEUIL_WARN=$((100-$WARNING))
SEUIL_CRIT=$((100-$CRITICAL))

#Detect which OS and if it is Linux then it will detect which Linux Distribution.
OS=`uname -s`

GetVersionFromFile()
{
	VERSION=`cat $1 | tr "\n" ' ' | sed s/.*VERSION.*=\ // `
}

if [ "${OS}" = "SunOS" ] ; then
	OS=Solaris
	DIST=Solaris
	ARCH=`uname -p`
elif [ "${OS}" = "AIX" ] ; then
	DIST=AIX
elif [ "${OS}" = "FreeBSD" ] ; then
	DIST=BSD
elif [ "${OS}" = "Linux" ] ; then
	KERNEL=`uname -r`
	if [ -f /etc/redhat-release ] ; then
		DIST='RedHat'
	elif [ -f /etc/system-release ] ; then
		DIST=`cat /etc/system-release | tr "\n" ' '| sed s/\s*release.*//`
	elif [ -f /etc/SuSE-release ] ; then
		DIST=`cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//`
	elif [ -f /etc/mandrake-release ] ; then
		DIST='Mandrake'
	elif [ -f /etc/debian_version ] ; then
		DIST="Debian `cat /etc/debian_version`"
	fi
	if [ -f /etc/UnitedLinux-release ] ; then
		DIST="${DIST}[`cat /etc/UnitedLinux-release | tr "\n" ' ' | sed s/VERSION.*//`]"
	fi
fi

#Define package format
case "`echo ${DIST}|awk '{print $1}'`" in
'RedHat')
PACKAGE="rpm"
;;
'Amazon')
PACKAGE="rpm"
;;
'SUSE')
PACKAGE="rpm"
;;
'Mandrake')
PACKAGE="rpm"
;;
'Debian')
PACKAGE="dpkg"
;;
'UnitedLinux')
PACKAGE="rpm"
;;
'Solaris')
PACKAGE="pkginfo"
;;
'AIX')
PACKAGE="lslpp"
;;
'BSD')
PACKAGE="pkg_info"
;;
esac

#Define locale to ensure time is in 24 hour format
LC_MONETARY=en_AU.UTF-8
LC_NUMERIC=en_AU.UTF-8
LC_ALL=en_AU.UTF-8
LC_MESSAGES=en_AU.UTF-8
LC_COLLATE=en_AU.UTF-8
LANG=en_AU.UTF-8
LC_TIME=en_AU.UTF-8

#Collect sar output
case "$PACKAGE" in
'rpm')
SARCPU=`/usr/bin/sar -P ALL|grep all|grep -v Average|tail -1`
SYSSTATRPM=`rpm -q sysstat|awk -F\- '{print $2}'|awk -F\. '{print $1}'`
if [ $SYSSTATRPM -gt 5 ]
 then
  SARCPUIDLE=`echo ${SARCPU}|awk '{print $8}'|awk -F. '{print $1}'`
  SARIOWAIT=`echo ${SARCPU}|awk '{print $6}'|awk -F. '{print $1}'`
  CPU=`echo ${SARCPU}|awk '{print "CPU Used = " 100-$8 "% IOWAIT = " $6 "% | " "CpuUser=" $3 "; CpuNice=" $4 "; CpuSystem=" $5 "; CpuIowait=" $6 ";'$IOWAIT_WARNING';'$IOWAIT_CRITICAL' CpuSteal=" $7 "; CpuIdle=" $8";'$SEUIL_WARN';'$SEUIL_CRIT'"}'`
 else
  SARCPUIDLE=`echo ${SARCPU}|awk '{print $7}'|awk -F. '{print $1}'`
  SARIOWAIT=`echo ${SARCPU}|awk '{print $6}'|awk -F. '{print $1}'`
  CPU=`echo ${SARCPU}|awk '{print "CPU Used = " 100-$7 "% IOWAIT = " $6 "% | " "CpuUser=" $3 "; CpuNice=" $4 "; CpuSystem=" $5 "; CpuIowait=" $6 ";'$IOWAIT_WARNING';'$IOWAIT_CRITICAL' CpuIdle=" $7";'$SEUIL_WARN';'$SEUIL_CRIT'"}'`
fi
;;
'dpkg')
SARCPU=`/usr/bin/sar -P ALL|grep all|grep -v Average|tail -1`
SYSSTATDPKG=`dpkg -l sysstat|grep sysstat|awk '{print $3}'|awk -F\. '{print $1}'`
if [ $SYSSTATDPKG -gt 5 ]
 then
  SARCPUIDLE=`echo ${SARCPU}|awk '{print $8}'|awk -F. '{print $1}'`
  SARIOWAIT=`echo ${SARCPU}|awk '{print $6}'|awk -F. '{print $1}'`
  CPU=`echo ${SARCPU}|awk '{print "CPU Used = " 100-$8 "% IOWAIT = " $6 "% | " "CpuUser=" $3 "; CpuNice=" $4 "; CpuSystem=" $5 "; CpuIowait=" $6 ";'$IOWAIT_WARNING';'$IOWAIT_CRITICAL' CpuSteal=" $7 "; CpuIdle=" $8";'$SEUIL_WARN';'$SEUIL_CRIT'"}'`
 else
  SARCPUIDLE=`echo ${SARCPU}|awk '{print $7}'|awk -F. '{print $1}'`
  SARIOWAIT=`echo ${SARCPU}|awk '{print $6}'|awk -F. '{print $1}'`
  CPU=`echo ${SARCPU}|awk '{print "CPU Used = " 100-$7 "% IOWAIT = " $6 "% | " "CpuUser=" $3 "; CpuNice=" $4 "; CpuSystem=" $5 "; CpuIowait=" $6 ";'$IOWAIT_WARNING';'$IOWAIT_CRITICAL' CpuIdle=" $7";'$SEUIL_WARN';'$SEUIL_CRIT'"}'`
fi
;;
'lslpp')
SARCPU=`/usr/sbin/sar -P ALL|grep "\-"|grep -v U|tail -2|head -1`
SYSSTATLSLPP=`lslpp -l bos.acct|tail -1|awk '{print $2}'|awk -F\. '{print $1}'`
if [ $SYSSTATLSLPP -gt 4 ]
 then
  CpuPhysc=`echo ${SARCPU}|awk '{print $6}'`
  LPARCPU=`/usr/bin/lparstat -i | grep "Maximum Capacity" | awk '{print $4}' |head -1`
  SARCPUIDLE=`echo "scale=2;100-(${CpuPhysc}/${LPARCPU}*100)" | bc | awk -F. '{print $1}'`
  SARIOWAIT=`echo ${SARCPU}|awk '{print $4}'|awk -F. '{print $1}'`
  PERFDATA=`echo ${SARCPU}|awk '{print "CpuUser=" $2 "; CpuSystem=" $3 "; CpuIowait=" $4 ";'$IOWAIT_WARNING';'$IOWAIT_CRITICAL' CpuPhysc=" $6 "; CpuEntc=" $7 "; CpuIdle=" $5";'$SEUIL_WARN';'$SEUIL_CRIT'"}'`
  CPU=`echo "CPU Idle = "${SARCPUIDLE}"% IOWAIT = "${SARIOWAIT}"%|" ${PERFDATA}"; LparCpuIdle="${SARCPUIDLE}"; LparCpuTotal="$LPARCPU`
 else
  echo "AIX $SYSSTATLSLPP Not Supported"
  exit 3
fi
;;
'pkginfo')
SARCPU=`/usr/bin/sar -u|grep -v Average|tail -2|head -1`
SYSSTATPKGINFO=`pkginfo -l SUNWaccu|grep VERSION|awk '{print $2}'|awk -F\. '{print $1}'`
if [ $SYSSTATPKGINFO -ge 11 ]
 then
  SARCPUIDLE=`echo ${SARCPU}|awk '{print $5}'`
  SARIOWAIT=`echo ${SARCPU}|awk '{print $4}'|awk -F. '{print $1}'`
  CPU=`echo ${SARCPU}|awk '{print "CPU Used = " 100-$5 "% IOWAIT = " $4 "% | " "CpuUser=" $2 "; CpuSystem=" $3 "; CpuIowait=" $4 ";'$IOWAIT_WARNING';'$IOWAIT_CRITICAL' CpuIdle=" $5";'$SEUIL_WARN';'$SEUIL_CRIT'"}'`
 else
  echo "Solaris $SYSSTATPKGINFO Not Supported"
  exit 3
fi
;;
'pkg_info')
SARCPU=`/usr/local/bin/bsdsar -u|tail -1`
SYSSTATPKGINFO=`pkg_info | grep ^bsdsar | awk -F\- '{print $2}' | awk -F\. '{print $1}'`
if [ $SYSSTATPKGINFO -ge 1 ]
 then
  SARCPUIDLE=`echo ${SARCPU}|awk '{print $6}'`
  SARIOWAIT=0
  CPU=`echo ${SARCPU}|awk '{print "CPU Used = " 100-$6 "% | " "CpuUser=" $2 "; CpuSystem=" $3 "; CpuNice=" $4 "; CpuIntrpt=" $5 "; CpuIdle=" $6";'$SEUIL_WARN';'$SEUIL_CRIT'""}'`
 else
  echo "BSD $SYSSTATPKGINFO Not Supported"
  exit 3
fi
;;
esac

#Display CPU Performance without alert
if [ "$ALERT" == "false" -a "$IOWAIT_ALERT" == "false" ]
 then
	echo "$CPU"
	exit 0
 else
        ALERT=true
	IOWAIT_ALERT=true
fi

#Display CPU Performance with alert
if [ ${SARCPUIDLE} -lt ${SEUIL_CRIT} -o ${SARIOWAIT} -gt ${IOWAIT_CRITICAL} ]
 then
		echo "CRITICAL: $CPU"
		exit 2
 elif [ ${SARCPUIDLE} -lt ${SEUIL_WARN} -o ${SARIOWAIT} -gt ${IOWAIT_WARNING} ]
		 then
		  echo "WARNING: $CPU"
		  exit 1
         else
		  echo "OK: $CPU"
		  exit 0
fi
