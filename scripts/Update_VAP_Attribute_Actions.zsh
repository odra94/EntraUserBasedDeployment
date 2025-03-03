#!/bin/zsh


################################################################################
# Variables to use across the script
################################################################################

PROD=false
declare -a jamf_email_addresses
microsoft_email_addresses=""
jamf_output="./jamf_output.txt"
graph_output="./graph_output.txt"
difference=""
new_ea_users=""
old_ea_users=""



################################################################################
# Jamf API Functions
################################################################################



# This uses the Github Actions secrets vault to get the client ID and client secret.
# You will need to set those variables up in Github Actions as secrets.
setJamfEnvironment() {
    if $1; then
        jamf_url="${JAMF_PROD_URL}"
        client_id="${JAMF_PROD_CLIENT_ID}"
        client_secret="${JAMF_PROD_CLIENT_SECRET}"
        smart_group_id="${JAMF_PROD_GROUP_ID}"
    else
        jamf_url="${JAMF_TEST_URL}"
        client_id="${JAMF_TEST_CLIENT_ID}"
        client_secret="${JAMF_TEST_CLIENT_SECRET}"
        smart_group_id="${JAMF_TEST_GROUP_ID}"
    fi
}


getAccessToken() {
    response=$(curl --silent --location --request POST "${jamf_url}/api/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${client_id}" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_secret=${client_secret}")
    access_token=$(echo "$response" | plutil -extract access_token raw -)
    token_expires_in=$(echo "$response" | plutil -extract expires_in raw -)
    token_expiration_epoch=$(($current_epoch + $token_expires_in - 1))
}

checkTokenExpiration() {
    current_epoch=$(date +%s)ß
    if [[ token_expiration_epoch -ge current_epoch ]]
    then
        echo "Token valid until the following epoch time: " "$token_expiration_epoch"
    else
        echo "No valid token available, getting new token"
        getAccessToken
    fi
}

invalidateToken() {
    responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${access_token}" $jamf_url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
    if [[ ${responseCode} == 204 ]]
    then
        echo "Token successfully invalidated"
        access_token=""
        token_expiration_epoch="0"
    elif [[ ${responseCode} == 401 ]]
    then
        echo "Token already invalid"
    else
        echo "An unknown error occurred invalidating the token"
    fi
}

# Update a user's EA to true
#
# Args:
#   username (string): username to update
updateUserEATrue() {
    local email="$1"
    
    # Check if the user exists
    local user_check_response=$(curl --silent --location --request GET \
        --url "$jamf_url/JSSResource/users/email/$email" \
        -H "Authorization: Bearer $access_token" \
        -H 'accept: application/xml')
    
    if [[ "$user_check_response" == *"Not Found"* ]]; then
        echo "User with email $email not found."
        echo ""
        return
    fi
    
    # If user exists, proceed to update
    local xml_data="
    <user>
        <extension_attributes>
            <extension_attribute>
                <id>1</id>
                <name>Automated Deployment</name>
                <type>String</type>
                <value>True</value>
            </extension_attribute>
        </extension_attributes>
    </user>
    "
    
    curl --silent --location --request PUT \
        --url "$jamf_url/JSSResource/users/email/$email" \
        -H "Authorization: Bearer $access_token" \
        -H 'accept: application/xml' \
        -H 'Content-Type: application/xml' \
        --data "$xml_data"
    echo "\nAdded EA for $email"
}

# Update a user's EA to false
#
# Args:
#   username (string): username to update
updateUserEAFalse() {
    local email="$1"
    
    # Check if the user exists
    local user_check_response=$(curl --silent --location --request GET \
        --url "$jamf_url/JSSResource/users/email/$email" \
        -H "Authorization: Bearer $access_token" \
        -H 'accept: application/xml')
    
    if [[ "$user_check_response" == *"Not Found"* ]]; then
        echo "User with email $email not found."
        echo ""
        return
    fi
    
    # If user exists, proceed to update
    local xml_data="
    <user>
        <extension_attributes>
            <extension_attribute>
                <id>1</id>
                <name>Automated Deployment</name>
                <type>String</type>
                <value>False</value>
            </extension_attribute>
        </extension_attributes>
    </user>
    "
    curl --silent --location --request PUT \
        --url "$jamf_url/JSSResource/users/email/$email" \
        -H "Authorization: Bearer $access_token" \
        -H 'accept: application/xml' \
        -H 'Content-Type: application/xml' \
        --data "$xml_data"
    echo "\nRemoved EA for $email"
}


# Get a list of email addresses for users in the smart group
#
# Gets a list of all users in the smart group and extracts their email addresses
# using xmllint. The email addresses are then saved to the jamf_email_addresses array.
getJamfUserEmails() {
    group_response=$(curl --silent --location -X 'GET' \
  "https://tamutest.jamfcloud.com/JSSResource/usergroups/id/$smart_group_id" \
  -H "accept: application/xml" \
  -H "Authorization: Bearer $access_token")

    # Use xmllint to extract the email addresses
    jamf_email_addresses=($(echo "$group_response" | xmllint --xpath "//user/email_address/text()" - | sort -u))
}

writeJamfUserEmailsFile() {
    echo "" > "$jamf_output"
    printf "%s\n" "${jamf_email_addresses[@]}" > "$jamf_output"
}

deleteJamfUserEmailsFile() {
    rm "$jamf_output"
}


################################################################################
# Microsoft Graph API Functions
# 
# We are only reading from Microsoft Entra so the functions are only
# performing read operations.
################################################################################

# Function to set up the environment for Microsoft Graph API
setGraphEnvironment() {
    graph_tenant_id=${GRAPH_TENANT_ID}
    graph_application_id=${GRAPH_APPLICATION_ID}
    graph_client_secret=${GRAPH_CLIENT_SECRET}
    graph_scope="https://graph.microsoft.com/.default"
    graph_url="https://login.microsoftonline.com/$graph_tenant_id/oauth2/v2.0/token"
    graph_group_id=${GRAPH_GROUP_ID}

    graph_response=$(curl --silent --location --request POST "$graph_url" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=$graph_application_id" \
        --data-urlencode "scope=$graph_scope" \
        --data-urlencode "client_secret=$graph_client_secret" \
        --data-urlencode "grant_type=client_credentials")

    graph_access_token=$(echo "$graph_response" | jq -r '.access_token')
    graph_token_expires_in=$(echo "$graph_response" | jq -r '.expires_in')
    graph_token_expiration_epoch=$(($(date +%s) + $graph_token_expires_in - 1))
}


# Function to get members of a group from Microsoft Graph
getGraphGroupMembers() {
    local group_id="$1"
    response=$(curl --silent --location --request GET "https://graph.microsoft.com/v1.0/groups/$group_id/members?\$select=mail" \
        --header "Authorization: Bearer $graph_access_token" \
        --header "Content-Type: application/json")

    microsoft_email_addresses=($(echo "$response" | jq -r '.value[] | .mail' | sort -u))
}

writeGraphGroupMembersFile() {
    printf "%s\n" "${microsoft_email_addresses[@]}" > "$graph_output"
}

deleteGraphGroupMembersFile() {
    rm "$graph_output"
}

################################################################################
# Processing Functions
################################################################################

getDifference() {
    #  Get the difference between the two files
    # It is important that the files stay in this same order or the other functions will
    # not work correctly.
    difference=$(diff "$jamf_output" "$graph_output")
}

getNewEAUsers() {
    new_ea_users=($(echo "$difference" | awk '/^>/ {print $2}'))
    echo "New EA Users: ${new_ea_users[@]}"
}

getRemovableEAUsers() {
    old_ea_users=($(echo "$difference" | awk '/^</ {print $2}'))
    echo "Removable EA Users: ${old_ea_users[@]}"
}

processNewEAUsers() {
    if [ ${#new_ea_users[@]} -eq 0 ]; then
        echo "No new EA users to process"
    else
        for email in "${new_ea_users[@]}"
        do
            updateUserEATrue "$email"
            echo "Added EA for $email"
        done
    fi
}

processRemovableEAUsers() {
    if [ ${#old_ea_users[@]} -eq 0 ]; then
        echo "No removable EA users to process"
    else
        for email in "${old_ea_users[@]}"
        do
            updateUserEAFalse "$email"
            echo "Removed EA for $email"
        done
    fi
}

# Process a list of new EA users from a CSV file. This function is a modified version of the processNewEAUsers function
# that reads email addresses from a CSV file.
#
# Args:
#   emails_csv (string): path to a CSV file containing email addresses of users
#                        to add to EA
processNewEAUsersFromCSV() {
    local emails_csv="$1"
    if [ ! -f "$emails_csv" ]; then
        echo "CSV file not found"
        exit 1
    else
        # Use tail to skip the header (first line)
        tail -n +2 "$emails_csv" | while IFS=, read -r email; do
            echo "Read email: $email"
            if [ -n "$email" ]; then
            updateUserEATrue "$email"
            echo "Added EA for $email"
            else
                echo "Empty email address found"
            fi
        done
    fi
}

# Process a list of removable EA users from a CSV file. This function reads
# email addresses from a CSV file and updates their EA status to false.
#
# Args:
#   emails_csv (string): path to a CSV file containing email addresses of users
#                        to remove from EA
processRemovableEAUsersFromCSV() {
    local emails_csv="$1"
    if [ ! -f "$emails_csv" ]; then
        echo "CSV file not found"
        exit 1
    else
        # Use tail to skip the header (first line)
        tail -n +2 "$emails_csv" | while IFS=, read -r email; do
            echo "Read email: $email"
            if [ -n "$email" ]; then
            updateUserEAFalse "$email"
                echo "Removed EA for $email"
            else
                echo "Empty email address found"
            fi
        done
    fi
}

# Process a Microsoft Entra user group.
#
# This function processes a Microsoft Entra user group by first setting up
# the Microsoft Graph environment, then getting the group members of the
# specified group ID, writing the members to a file, and printing the file
# contents.
processMicrosEntraUserGroup() {
setGraphEnvironment

# echo "Group ID: $graph_group_id"
getGraphGroupMembers "$graph_group_id"

echo ""
echo "Microsoft Group Members: ${microsoft_email_addresses[@]}"
echo ""

writeGraphGroupMembersFile

echo "Graph Group Members File:"
cat "$graph_output"
}


# Process the specified server (production or test).
#
# This function processes the specified server by setting up the Jamf
# environment, getting the access token, getting the list of users in the
# smart group, writing the list of users to a file, getting the difference
# between the two lists of users, figuring out which users are new and which
# users are removable, processing those users, and then cleaning up.
processServer() {
    local production=$1

    # Set Environment
    setJamfEnvironment $production

    # Get Access Token
    getAccessToken

    getJamfUserEmails

    echo ""
    echo "Jamf Group Members: ${jamf_email_addresses[@]}"
    echo ""

    writeJamfUserEmailsFile

    echo "Jamf Group Members File:"
    cat "$jamf_output"

    getDifference

    echo ""
    echo "Difference: ${difference[@]}"
    echo ""

    getNewEAUsers

    getRemovableEAUsers

    processRemovableEAUsers

    processNewEAUsers

    deleteJamfUserEmailsFile

    deleteGraphGroupMembersFile

    invalidateToken
}

################################################################################
# Run the Workflow
################################################################################

# Process the Test Server
PROD=false
processMicrosEntraUserGroup

processServer $PROD
