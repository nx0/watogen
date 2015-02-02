#!/bin/bash

TITLE_TEXT="Web Administration Tool Host Generator"
FOOTER_TXT="bugs, etc: hackgo@gmail.com"

echo "
               _  [ $TITLE_TEXT ]                       
__      ____ _| |_ ___   __ _  ___ _ __  
\ \ /\ / / _  | __/ _ \ / _  |/ _ \ '_ \ 
 \ V  V / (_| | || (_) | (_| |  __/ | | |
  \_/\_/ \__,_|\__\___/ \__, |\___|_| |_|
                        |___/ $FOOTER_TXT
"

######### COLOR SETUP #########
GREEN=`tput setaf 2`
RED=`tput setaf 3`
ENDCOLOR=`tput sgr0`
######### COLOR SETUP #########

function reload {
	cmk -R
}

function scanips {
	# ARG 1: Rango
	# ARG 2: Opción de solo escaneo o nombre para crear carpeta en wato
	# ARG 3: Nombre de la carpeta wato

	if [ "${1}" != "" ]; then
		savescan="/tmp/$(echo ${1}| sed 's/\./_/g' | sed 's/\//-/g').txt"
		> $savescan
		echo "[*] Guardando resultados en ${savescan} ... "
		#echo `nmap -sP ${1} -vv| grep -B2 "MAC Address" | grep -E "report|MAC" | grep -Eo "([0-9]{1,3}\.?){4}|\(.*?\)"` | sed 's/(/ /g' | sed 's/)/\n/g' | sed 's/^ //g' | sed "s/'/_/g" | sed '/^$/d' >> ${savescan}
		cont=0 
		nmap -sP ${1} | grep "scan report for"| awk '{ print $5 " " $6 }'| sed 's/^ //g' | sed '/^$/d' |
		while read ip; do
			echo "[>>] $ip"
			# DETECCION DE IP MEJORADA
			if [ "`echo \"$ip\" | awk '{ print $1 }' | grep -E '([0-9]\.?){4}'`" != "" ]; then 
				# nmblookup -T -A IP
				echo -n "[$ip] sin DNS, probando snmp..."
				snmpname=`snmpget -c public -v 2c $ip iso.3.6.1.2.1.1.1.0 2>/dev/null| grep -v "No Response" | awk '{ print $5 }'`
				if [ "${snmpname}" != "" ]; then
					echo " OK (${snmpname})"
					echo "SNMPDNS_$snmpname $(echo $ip| awk '{ print $1 }')" >> $savescan
				else
					echo " ERROR!"
					echo "NO_DNS $(echo $ip| awk '{ print $1 }')" >> $savescan
				fi
			else
				echo $ip | tr -d "(" | tr -d ")" >> $savescan
			fi
			cont=`wc -l $savescan | awk '{ print $1 }'`
		done
		echo "... Completado con ($cont) hosts."
		case ${2} in
			"onlyscan")
				exit 0
				;;
			*)
				filex ${savescan} ${2}
		esac
	else
		echo "rango de ip no especificado. Especifica XXX.XXX.XXX.XXX/XX"
	fi
}

# PARSEADOR
function filex {

	# ARG 1 => nombre del fichero
	# ARG 2 => nombre de la carpeta en wato

	# ESCANEA UN ARCHIVO QUE SE LE PASA COMO ARGUMENTO
	# LLAMA A PARSE PARA GENERAR LA CONFIGURACION
	#folder=`basename $1`

	ipfile=$1
	folder=$2
	if [ -f "${1}" ]; then
		echo -n "Analizando $1 "
		echo "(`cat $1 | wc -l` hosts)"
		if [ ! -d "/etc/check_mk/conf.d/wato/$folder/" ]; then
			mkdir "/etc/check_mk/conf.d/wato/$folder/"
			parse $folder $ipfile
		else
			echo -n "la carpeta $folder ya existe, quieres actualizar los hosts? [y]/n: "
			read resp
			case $resp in
				*|"y")
					echo "# ---- FICHERO GENERADO POR WATOGEN ----" > "/etc/check_mk/conf.d/wato/$folder/hosts.mk"
					parse $folder $ipfile
					;;
				"n")
					exit 0
					;;
			esac
		fi
		chown apache:nagios -R "/etc/check_mk/conf.d/wato/$folder/"
	else
		echo "el fichero ${1} no existe"
	fi
}

# PARSEAR LA CONFIGURACION 
function genconfig {
	filewato="${2}"
	file_to_read="${3}"

	cat ${file_to_read} |sed '/^$/d' | sort | while read line; do
        	ip="`echo $line| grep -Eo '(([0-9]{1,3}+\.){3}[0-9]{1,3})'`"
        	model="`echo $line | awk '{ print $1 }'`"
		
		case $model in 
			"NO_DNS")
				model="$ip"
				attr_string="'$ip': {'alias': u'NO_DNS', 'inventory_failed': True, 'ipaddress': u'$ip'},"
			;;
			SNMPDNS_*)
				model="`echo $model | awk -F 'SNMPDNS_' '{ print $2 }'`"
				attr_string="'$model': {'alias': u'SNMP_DNS', 'inventory_failed': True, 'ipaddress': u'$ip'},"
			;;
			*)
				attr_string="'$model': {'inventory_failed': True, 'ipaddress': u'$ip'},"
		esac

		if [ "${1}" == "all" ]; then
			echo "\"$model|ping|wato|/\" + FOLDER_PATH + \"/\"," >> $filewato
		elif [ "${1}" == "ip" ]; then
			echo "'$model': u'$ip'," >> $filewato
		elif [ "${1}" == "attrib" ]; then
			echo "$attr_string" >> $filewato
		else
			echo "nope"
		fi	
	done
}

# CREAR LA CONFIGURACION
function parse {
	file_to_parse=${2}
	hostfile="/etc/check_mk/conf.d/wato/$1/hosts.mk"
	echo "[*] Generando $hostfile"
	echo "all_hosts += [" >> $hostfile
		echo -n "[-] Añadiendo ips ..."
		genconfig all $hostfile $file_to_parse
		echo " OK"
	echo "]

	" >> $hostfile


	echo "ipaddresses.update({" >> $hostfile
		echo -n "[-] Generado IPS ..."
		genconfig ip $hostfile $file_to_parse
		echo " OK"
	echo "})
	
	" >> $hostfile


	echo "host_attributes.update({" >> $hostfile
		echo -n "[-] Generado atributos ..."
		genconfig attrib $hostfile $file_to_parse
		echo " OK"
	echo "})" >> $hostfile
}



####################################################################################################
# ENTRY POINT
####################################################################################################

case ${1} in
	""|"help")
		echo "Elige un modo para descubrir equipos:"
		echo "	$0 [--mode] [network [--rango RANGO-IP] <onlyscan>|--name [NAME]|file [--location LOCATION.txt]] <reload>"
		echo "	* Ejemplo de uso:"
		echo "	# $0 --mode network --rango 192.168.1.0/24 --name red_local"
		echo "	# $0 --mode network --rango 192.168.1.0/24 onlyscan"
		echo "	# $0 --mode file --ipfile /tmp/algo.txt --folder red_local"
		echo "	# $0 --mode manual host.doma.in --folder red_local"
		echo "	* Modos de uso:"
		echo "	- network: Escanea un rango dado para descubrir equipos"
		echo "	- file: Lee un fichero de texto para añadir equipos (formato: DNS IP)"
		echo "	# $0 --list"
	;;
	"--mode")
		case ${2} in
			"network")
				case ${3} in
					"--rango")
						rango=${4}
						options_for_rango=${5}
						name=${6}	
						case ${options_for_rango} in
							"onlyscan")
								scanips ${rango} onlyscan
							;;
							"--name")
								if [ "${name}" != "" ]; then
									scanips ${rango} ${name}
									if [ "${7}" == "reload" ]; then
                                                                        	reload
									fi
								else
									echo "Faltan argumentos. Opciones disponibles: [--name [NAME]]"
								fi
							;;
							*)
								echo "Faltan argumentos!"
								echo "Opciones disponibles: [onlyscan|--name [NAME]]"
						esac
						;;
					*)
						echo "Error!" 
						echo "Opciones disponibles: [--rango [RANGO IP]]"
						exit 0
				esac
			;;
			"file")
				options_for_file="${5}"
				ipfile=${4}
				folder_name="${6}"
				if [ -f "$ipfile" ]; then
					case ${options_for_file} in
						"--folder")
							if [ "$folder_name" != "" ]; then
								filex "${ipfile}" "${folder_name}"
								if [ "${7}" == "reload" ]; then
									reload
								fi
							else
								echo "Especifica un nombre válido para la carpeta"
							fi
						;;
						*)
							echo "Faltan argumentos!"
							echo "Opciones disponibles: [--folder [FOLDER NAME]]"
					esac
				else
					echo "no existe: $ipfile"
					exit 0
				fi
			;;
			"manual")
				echo "buscando $3"
				find /etc/check_mk/conf.d/wato/ | xargs grep -i $3
				if [ $? -eq 0 ]; then
					echo "servidor ya añadido"
				fi
			;;
			*)
				echo "Faltan argumentos!"
				echo "Opciones disponibles: [network|file]"
		esac
	;;
	"--list")
		for xx in `find /etc/check_mk/conf.d/wato/ -type d`; do
			echo "[ $xx ]"
			for dd in $xx; do
				find $dd -name "hosts.mk" | xargs sed -n '/\[/,/\]/p' | awk -F '|' '{ print $1 }' | grep -vE 'hosts|\[|\]' | awk -F '"' '{ print $2 }' | sed '/^$/d'
			done	
			echo " "
		done
	;;
	"--manual")
		echo "we"
		find /etc/check_mk/conf.d/wato/ | xargs grep -i $2
	;;
	*)
		echo "Opción inválida!"
		echo "Opciones disponibles: [network|file]"

esac
