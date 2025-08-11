PingCastle Notify
===

PingCastle Notify is a tool that will monitor your PingCastle reports ! You will be notified every time a change between a scan and a previous scan is made.

How it works ? PingCastle-Notify is a PS1 script that will run a PingCastle scan, compare the difference between a previous scan, highlight the diff and send the result into a Slack / Teams channel or a log file !

The slack/teams/log message will notify you regarding the different states: correction, recession etc

<p align="center">

![image](https://github.com/LuccaSA/PingCastle-Notify/assets/5891788/35eb7e52-600e-4c15-bcb3-f57bf0b2a89f)

> :warning: If you don't want to use Slack or Teams set `SLACK_ENABLED=0` and `TEAMS_ENABLED=0` in the `.env` file. Skip the step "Create a BOT" and check the log file inside the **Reports** folder.

</p>
<hr>
<details>
<summary>:arrow_forward: <b>First scan</b></summary>

Slack             | Teams
:-------------------------:|:-------------------------:
![image](https://user-images.githubusercontent.com/5891788/191265007-57656f04-12ed-4e93-af36-90b0711aa412.png)  |   ![image](https://user-images.githubusercontent.com/5891788/193760283-ef171f2d-6992-44b7-ad8e-8b3f113ffe3d.png)


</details>
<details>
<summary>:arrow_forward: <b>No new vulnerability but some rules have been updated</b></summary>

![image](https://user-images.githubusercontent.com/5891788/191266282-cd790c58-76df-4116-89fa-4aa954f0dd7e.png)

</details>
<details>

<summary>:arrow_forward: <b>New vulnerabilty</b></summary>

Slack             | Teams
:-------------------------:|:-------------------------:
![image](https://user-images.githubusercontent.com/5891788/191268156-cb1c1884-beef-421e-9aae-75661e071abf.png)  |   ![image](https://user-images.githubusercontent.com/5891788/193760136-668fca48-9ddf-47dd-b82a-0708117954f1.png)


</details>
<details>
<summary>:arrow_forward: <b>Some vulnerability have been removed</b></summary>

Slack             | Teams
:-------------------------:|:-------------------------:
![image](https://user-images.githubusercontent.com/5891788/191265798-0ef01763-6401-4c51-9d7d-8bf6f5ab246d.png)   |   ![image](https://user-images.githubusercontent.com/5891788/193760223-8658c35c-0ef3-4012-8679-8946987f4e4a.png)
 


</details>
<details>
<summary>:arrow_forward: <b>No new vulnerability</b></summary>

No result in slack since reports are the same
</details>

---
<details>
<summary>:beginner: <b>Adding the result of the current scan</b></summary>

Set the variable `$print_current_result` to 1 in the script, the rules flagged on the current scan will be added as a thread into Slack or after the rule diff on Teams.

Slack             | Teams
:-------------------------:|:-------------------------:
![image](https://user-images.githubusercontent.com/5891788/194527966-f13e0f85-cff6-4e22-86b1-00f871b29cc2.png)  |   ![Teams_8N2r3YiVh4](https://user-images.githubusercontent.com/5891788/194527837-8f6f0910-aa17-47d2-bfee-01d4defa569b.png)
</details>



## How to install ?

### Structure of the project

```
SECU-TOOL-SCAN/
    - PingCastle-Notify.ps1
    - .env                  <-- Configuration file
    - modules/
        - Slack.psm1
        - Teams.psm1
    - PingCastle/
        - Reports/
            - domain.local.xml
            - domain.local.html
            - scan.logs <-- contains the logs of the scan (diff scan)
        - Pingcastle.exe
        - ...
```

#### PingCastle & PingCastle-Notify.ps1

1. Download PingCastle
2. Unzip the archive
3. Create a "**Reports**" folder inside the PingCastle folder
4. Download the PingCastle-Notify repository
5. Copy `.env.example` to `.env` and configure your settings

#### Configuration

Create a `.env` file in the root directory with your configuration:

```bash
# Copy the example file
cp .env.example .env
```

Then edit the `.env` file with your settings:

```properties
# Slack Configuration
SLACK_CHANNEL=#pingcastle-scan
SLACK_TOKEN=xoxb-your-slack-bot-token-here
SLACK_ENABLED=1

# Teams Configuration  
TEAMS_ENABLED=0
TEAMS_URI=https://your-org.webhook.office.com/webhookb2/your-webhook-url-here

# Report Configuration
PRINT_CURRENT_RESULT=1

# Domain Configuration
DOMAIN=your-domain.local
```

**Configuration Options:**
- `SLACK_ENABLED`: Set to `1` to enable Slack notifications, `0` to disable
- `SLACK_CHANNEL`: The Slack channel to send notifications to (include the #)
- `SLACK_TOKEN`: Your Slack bot token (starts with `xoxb-`)
- `TEAMS_ENABLED`: Set to `1` to enable Teams notifications, `0` to disable
- `TEAMS_URI`: Your Teams webhook URL
- `PRINT_CURRENT_RESULT`: Set to `1` to include current scan results in notifications
- `DOMAIN`: Your domain name (optional, will use `$env:USERDNSDOMAIN` if not set)

## Usage

### Basic Usage

Run the script to perform a PingCastle scan and send notifications:

```powershell
.\PingCastle-Notify.ps1
```

### Advanced Usage

#### No-Scan Mode

Skip the PingCastle scan and only process existing reports:

```powershell
.\PingCastle-Notify.ps1 -noscan
```

This mode is useful for generating the diff without running PingCastle.exe in case you already send all the report into a custom share.

**Note:** The `-noscan` mode requires existing PingCastle reports to be present in the expected location.

#### Verbose Output

Enable detailed information output for debugging:

```powershell
.\PingCastle-Notify.ps1 -InformationAction Continue
```

Or combine with noscan mode:

```powershell
.\PingCastle-Notify.ps1 -noscan -InformationAction Continue
```

#### Create a BOT

<details>
<summary>:arrow_forward: <b>Slack BOT</b></summary>

1. In Slack create an application https://api.slack.com/apps
2. Add the following rights
   - Click on "Add features and functionality" -> Bots (configure the name)
   - Click on "Add features and functionality" -> Permissions (add the following permissions)
   - Generate a "Bot User OAuth Token" on the Permissions tab
   
![image](https://user-images.githubusercontent.com/5891788/191264679-7942173b-bb1f-4dd1-a936-4e97acdb1b5e.png)

3. Get your token and add it to the `.env` file as `SLACK_TOKEN`
4. Create a slack channel and add your bot user to the channel
5. You can test your bot using https://api.slack.com/methods/chat.postMessage/test
6. Add the channel to the `.env` file as `SLACK_CHANNEL`
7. Set `SLACK_ENABLED=1` in your `.env` file
8. Run the script to test using this command: 
   `powershell.exe -exec bypass C:\YOUR_PATH\SECU-TOOL-SCAN\PingCastle-Notify.ps1`
</details>
<details>
<summary>:arrow_forward: <b>Teams BOT</b></summary>

1. Create a channel **pingcastle-scan**
2. Click on the "..." dots and select "Connectors"
3. Search for **Webhook**
4. Add the webhook
5. Re-click on the connectors button and on the webhook click **"configure"**
6. Add a title and a logo and click **Create**, copy the webhook URL
7. Update the `.env` file:
   - Set `TEAMS_ENABLED=1`
   - Set `TEAMS_URI` to your webhook URL
</details>
<details>
<summary>:arrow_forward: <b>Teams WorkFlow (prefered for Teams)</b></summary>

1.  **Start a new workflow:** In Microsoft Teams, navigate to your desired channel, click the three dots (`...`), and select **Workflows**. Then, click **Create a workflow**.
2.  **Set the trigger:** Search for and select the trigger **"When a Teams webhook request is received."** This action provides a unique URL that will listen for incoming POST requests.
3.  **Add a new action:** Click on **New step**.
4.  **Configure the action:** Search for and select the action **"Post message in a chat or channel."**
    * For **Post as**, choose `Flow bot` to ensure the message comes from the workflow itself.
    * Select the **Team** and **Channel** where the message should be posted.
5.  **Define the message content:** In the `Message` field, click on the **Expression** tab. Enter the following expression:
    `triggerBody()?['pingcastle']`
    This expression tells the workflow to look for a key named `pingcastle` within the JSON payload of the incoming webhook request and use its value as the message content.
6.  **Save and get the URL:** Save the workflow. Once saved, expand the trigger step **"When a Teams webhook request is received."** The unique **HTTP POST URL** will be displayed there.
You can now use this URL to send a message to the Teams channel. Any POST request to this URL with a JSON body containing a key named `pingcastle` will have the corresponding value posted as a message.
7. Update the `.env` file
</details>

#### Deploy a Scheduled Task

On your Windows Server go to

1. Create a service account that will run the PS1 script every night (no need to set the service account as domain admin)
2. Give privileges to the service account on the folder "Reports"

![image](https://user-images.githubusercontent.com/5891788/191264615-ab0b9479-b869-4cbf-9e74-499ca0b38c4e.png)

3. Run taskschd.msc to open the Scheduler Task
4. Create a Task and use the service account you just created
5. In Actions tab set "Start a program" -> "Script": `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` -> "Arguments" -> `-exec bypass -f C:\PINGCASTLE\Pingcastle-Notify.ps1`
6. Give the permission "Log on as Batch Job" to service account https://danblee.com/log-on-as-batch-job-rights-for-task-scheduler/
7. Run the scheduled task to test the result
8. Enjoy :)

<p align="center">
<img width="600" height="400" src="https://user-images.githubusercontent.com/5891788/191264530-bb4f2700-d91b-4e94-8bb8-ea57238e90ca.png">
<img src="https://user-images.githubusercontent.com/5891788/191264565-a5fe4a3c-b14d-4e5a-b6c0-efe741d4591d.png">
<img src="https://user-images.githubusercontent.com/5891788/191264503-cb3155a9-f2b3-4fed-b6de-eaf35b47a545.png">
</p>

## Adding a New Connector

The PingCastle-Notify system is designed to be easily extensible. You can add new notification connectors (Discord, Email, SMS, etc.) by creating a new module file.

### Step 1: Create the Module File

Create a new PowerShell module file in the `modules` folder:
```
modules/YourConnector.psm1
```

### Step 2: Test Your Connector

1. Place your module file in the `modules` folder
2. Add configuration to `.env`
3. Run the script - your connector will be automatically discovered and loaded
4. Check the console output for "Loading module: YourConnector"

### Notes

- **No changes needed** to the main script when adding new connectors
- The system automatically discovers all `.psm1` files in the `modules` folder
- Function names must follow the pattern: `FunctionName-YourConnectorName`
- Your connector will only be used if enabled in the `.env` file
- Both hashtable and string body types are supported

## Acknowledgement

- Vincent Le Toux - https://twitter.com/mysmartlogon
- Romain Tiennot - https://github.com/aikiox
- Lilian Arago - https://github.com/NahisWayard
- Romain Bourgue - https://github.com/raomin

## License

MIT License

