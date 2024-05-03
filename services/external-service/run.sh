# This script takes an argument for the url of the counter-service
# which the external-service will use to get visit counter

cd "$(dirname "$0")"

# $1 is the command line argument for the url of the counter-service
URL=$1 python3 -m hypercorn app:app --bind 0.0.0.0:8080
