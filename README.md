PingCastle Notify
===

PingCastle Notify is a tool that will monitor your PingCastle reports ! You will be notified every time a change between a scan and a previous scan is made.

How it works ? PingCastle-Notify is a PS1 script that will run a PingCastle scan, compare the difference between a previous scan, highlight the diff and send the result into a Slack / Teams channel or a log file !

The slack/teams/log message will notify you regarding the different states: correction, recession etc

<p align="center">

![image](https://user-images.githubusercontent.com/5891788/193772010-949bd9d4-4d73-4df6-ad24-5ee2115fa9b2.png)


> :warning: If you don't want to use Slack or Teams set the variable `$teams` and `$slack` to 0 inside the ps1 script. Skip the step "Create a BOT" and check the log file inside the **Reports** folder.

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
4. Download and add the file `PingCastle-Notify.ps1` on the parent directory

#### Create a BOT

<details>
<summary>:arrow_forward: <b>Slack BOT</b></summary>

1. In Slack create an application https://api.slack.com/apps
2. Add the following rights
   - Click on "Add features and functionality" -> Bots (configure the name)
   - Click on "Add features and functionality" -> Permissions (add the following permissions)
   - Generate a "Bot User OAuth Token" on the Permissions tab
   
![image](https://user-images.githubusercontent.com/5891788/191264679-7942173b-bb1f-4dd1-a936-4e97acdb1b5e.png)

3. Get your token add it to the PingCastle-Notify.ps1 script
4. Create a slack channel and add your bot user to the channel
5. You can test your bot using https://api.slack.com/methods/chat.postMessage/test
6. Add the channel to the script
7. Run the script to test using this command: 
   `powershell.exe -exec bypass C:\YOUR_PATH\SECU-TOOL-SCAN\PingCastle-Notify.ps1`
</details>
<details>
<summary>:arrow_forward: <b>Teams BOT</b></summary>

1. Create a channel **pingcastle-scan**
2. Click on the "..." dots and select "Connectors"
3. Search for **Webhook**
4. Add the webhook
5. Re-click on the connectors button and on the webhook click **"configure"**
6. Add a title and a logo and click **Create**, copy the wehbook URL
7. Add the url on the variable `$teamsUri`
8. Set the variable `$teams` to 1 and `$slack` to 0
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

## Acknowledgement

- Vincent Le Toux - https://twitter.com/mysmartlogon
- Romain Tiennot - https://github.com/aikiox
- Lilian Arago - https://github.com/NahisWayard
- Romain Bourgue - https://github.com/raomin

## License

MIT License
