# EntraUserBasedDeployment

This repo is an example that can be used for an automated deployment that is based on a user group made in Microsoft Entra.  

The workflow takes care of comparing the membership of a smart user group in Jamf Pro against the membership of a security group in Microsoft Entra.

If there is a member in the Jamf smart user group that is not in the Entra security group then it will remove that user from the deployment. The Entra security group is the source of truth in this deployment so the smart user group has to match the Entra security group as closely as possible.

If there is a member in the Entra security group that is not in the Jamf smart user group, then it will modify the extension attribute of that user and add them to the deployment.

Additionally, I have left in the code a lot of standard output to see what is happening as the script is running. Basically a lot of `echo` commands so you can see what the script is doing. Those can be removed and cleaned up for final deployment. For purposes of this example they have been left in there and I am also just running the commands on the test server. This means only the variables with the prefix `JAMF_TEST` are the only relevant Jamf related variables being used for this example.

## Microsoft Entra

Ensure that you create an enterprise app registration in Microsoft Entra.  

### Secrets Needed:
Gather the following information for the secrtes you will need for the Microsoft Entra calls:  
`GRAPH_APPLICATION_ID`: The Application ID of your app registration  
`GRAPH_CLIENT_SECRET`: Create a client secret for your registered app. Grab that secret and store it in the secrets vault for your GitHub repository. Make sure it is a secret and not just a variable.  
`GRAPH_GROUP_ID`: This is the Object ID of your entra group  
`GRAPH_TENANT_ID`: Your entra [Tenant ID](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-find-tenant)  

### API Permissions Needed for your App Registration:

For this example we used two permissions:

`GroupMember.Read.All`  
`User.ReadBasic.All`  

These allowed the microsoft graph calls to give us only the necessary information to go through with the deployment.

## Jamf Pro

### User Extension Attribute

Create a user Extension Attribute to use for the deployment. The name and descriptions are up to you.

Extension Attribute Data Type: `String`  

Extension Attribute Input Type: `Text Field`  

<!-- <p align="center">
  <img src="/images/ExtensionAttribute.png" width="900;"/>
</p> -->

<p align="center">
  <img src="/images/ExtensionAttribute.png"/>
</p>

### User Smart Group:

Create a smart user group that is based on the extension attribute you created. You will use this as the scope group in your policy.  

<p align="center">
  <img src="/images/SmartUserGroup.png" width="900;"/>
</p>

### Secrets Needed:

Gather the following information for your secrets. You may only need half of these variables if you are running the workflow on just one server. Remember to modify the script accordingly.  

`JAMF_PROD_CLIENT_ID`: Jamf production server client ID  
`JAMF_PROD_CLIENT_SECRET`: Jamf production server client secret  
`JAMF_PROD_GROUP_ID`: This is the group id of the smart group you create in your production server for tracking the changes to the extension attribute.  
`JAMF_PROD_URL`: Jamf production server URL  

`JAMF_TEST_CLIENT_ID`: Jamf test server client ID  
`JAMF_TEST_CLIENT_SECRET`: Jamf test server client secret  
`JAMF_TEST_GROUP_ID`: This is the group id of the smart group you create in your test server for tracking the changes to the extension attribute.  
`JAMF_TEST_URL`: Jamf test server URL  

### Privileges Needed for Your Jamf API Role:
`Update User`  
`Read Smart User Groups`  
`Read User`  

## GitHub Actions

Example of secrets you will need to populate:  
`GRAPH_APPLICATION_ID`  
`GRAPH_CLIENT_SECRET`  
`GRAPH_GROUP_ID`  
`GRAPH_TENANT_ID`  
`JAMF_PROD_CLIENT_ID`  
`JAMF_PROD_CLIENT_SECRET`  
`JAMF_PROD_GROUP_ID`  
`JAMF_PROD_URL`  
`JAMF_TEST_CLIENT_ID`  
`JAMF_TEST_CLIENT_SECRET`  
`JAMF_TEST_GROUP_ID`  
`JAMF_TEST_URL`  

We have two servers, one for testing and another one for porduction. This means you may not need as many variables as we are using. You can update the script to fit your needs.

In this repository there is also a `manual.yaml` file to run the action manually. So assuming you setup everything above you could in theory actually run the workflow and test it.

I would recommend you modify it to fit your needs and even run the script locally on your device before putting it up in github actions.