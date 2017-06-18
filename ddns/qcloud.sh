#!/bin/sh

set -e

if [ $1 ]; then
	SecretId=$1
fi

if [ $2 ]; then
	SecretKey=$2
fi

if [ $3 ]; then
	Domain=$3
fi

if [ -z "$SecretId" -o -z "$SecretKey" -o -z "$Domain" ]; then
	echo "Missing parameters"
	exit 1
fi

if [ $4 ]; then
	SubDomain=$4
fi

if [ -z "$SubDomain" ]; then
	SubDomain="@"
fi

ErrorMessage=""

# $1 = query string
getSignature() {
	local message="GETcns.api.qcloud.com/v2/index.php?$1"
	local sig=$(echo -n "$message" | openssl dgst -sha256 -hmac "$SecretKey" -binary | openssl base64)
	sig=$(echo $sig | sed 's:+:%2B:g')
	sig=$(echo $sig | sed 's:/:%2F:g')
	sig=$(echo $sig | sed 's:=:%3D:g')
	echo $sig
}

sendRequest() {
	local nonce=$RANDOM
	local timestamp=$(date '+%s')
	local query="Action=$1&Nonce=$nonce&Region=sh&SecretId=$SecretId&SignatureMethod=HmacSHA256&Timestamp=$timestamp&$2"
	local signature=$(getSignature $query)
	local result=$(wget -qO- --no-check-certificate "https://cns.api.qcloud.com/v2/index.php?$query&Signature=$signature")
	echo $result
}

getRecordId() {
	echo "Retreiving the record ID of $SubDomain.$Domain..." >&2
	local result=$(sendRequest "RecordList" "domain=$Domain&recordType=A&subDomain=$SubDomain")
	local code=$(echo $result | jq -r '.code')
	
	if [ "$code" = "0" ]; then
		local ip=$(echo $result | jq -r '.data.records[0].value')

		if [ "$ip" = "$NewIP" ]; then
			echo "IP remains the same, quiting the script..." >&2
			exit 1
		fi

		local recordId=$(echo $result | jq -r '.data.records[0].id')
		echo $recordId
	else
		ErrorMessage=$(echo $result | jq -r '.message')
		echo "null"
	fi
}

# $1 = record ID, $2 = new IP
updateRecord() {
	local result=$(sendRequest "RecordModify" "domain=$Domain&recordId=$1&recordLine=默认&recordType=A&subDomain=$SubDomain&value=$2")
	local code=$(echo $result | jq -r '.code')
	
	if [ "$code" = "0" ]; then
		local recordId=$(echo $result | jq -r '.data.record.id')
		echo $RecordId
	else
		ErrorMessage=$(echo $result | jq -r '.message')
		echo "null"
	fi
}

# $1 = new IP
addRecord() {
	local result=$(sendRequest "RecordCreate" "domain=$Domain&recordLine=默认&recordType=A&subDomain=$SubDomain&value=$1")
	local code=$(echo $result | jq -r '.code')
	
	if [ "$code" = "0" ]; then
		local recordId=$(echo $result | jq -r '.data.record.id')
		echo $recordId
	else
		ErrorMessage=$(echo $result | jq -r '.message')
		echo "null"
	fi
}

# Get new IP address
echo "Retreiving current IP..."
NewIP=$(wget -qO- http://members.3322.org/dyndns/getip)
echo "Current IP $NewIP is retrieved."

# Get record ID of sub domain
RecordId=$(getRecordId)

if [ "$RecordId" = "null" ]; then
	echo "Record ID does not exist."
	echo "Creating $SubDomain.$Domain to $NewIP..."
	RecordId=$(addRecord $NewIP)
else
	echo "Record ID $RecordId exists."
	echo "Updating $SubDomain.$Domain to $NewIP..."
	RecordId=$(updateRecord $RecordId $NewIP)
fi
	
if [ "$RecordId" = "null" ]; then
	echo "Failed to update IP of $SubDomain.$Domain."
	echo $ErrorMessage
else
	echo "$SubDomain.$Domain => $NewIP, IP updated."
fi