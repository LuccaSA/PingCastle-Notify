PingCastle Notify
===

PingCastle Notify will run a PingCastle scan, compare the difference between a previous scan, highlight the diff and send the result into a Slack channel.
The slack message will notify you regarding the different states: correction, recession etc
<p align="center">

<img src="https://user-images.githubusercontent.com/5891788/191265253-24f23845-b9e9-4dd2-9ffe-021f7ae7af70.png">

</p>
<hr>
<details>
<summary>:arrow_forward: <b>First scan</b></summary>

![image](https://user-images.githubusercontent.com/5891788/191265007-57656f04-12ed-4e93-af36-90b0711aa412.png)
</details>
<details>
<summary>:arrow_forward: <b>No new vulnerability but some rules have been updated</b></summary>

![image](https://user-images.githubusercontent.com/5891788/191266282-cd790c58-76df-4116-89fa-4aa954f0dd7e.png)

</details>
<details>

<summary>:arrow_forward: <b>New vulnerabilty</b></summary>

![image](https://user-images.githubusercontent.com/5891788/191268156-cb1c1884-beef-421e-9aae-75661e071abf.png)
</details>
<details>
<summary>:arrow_forward: <b>Some vulnerability have been removed</b></summary>

![image](https://user-images.githubusercontent.com/5891788/191265798-0ef01763-6401-4c51-9d7d-8bf6f5ab246d.png)  
</details>
<details>
<summary>:arrow_forward: <b>No new vulnerability</b></summary>

No result in slack since reports are the same
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
        - Pingcastle.exe
        - ...
```

#### PingCastle & PingCastle-Notify.ps1

1. Download PingCastle
2. Unzip the archive
3. Create a "**Reports**" folder inside the PingCastle folder
4. Download and add the file `PingCastle-Notify.ps1` on the parent directory

#### Create a Slack application

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

#### Deploy a Scheduled Task

On your Windows Server go to

1. Create a service account that will run the PS1 script every night
2. Give privileges to the service account on the folder "Reports"

![image](https://user-images.githubusercontent.com/5891788/191264615-ab0b9479-b869-4cbf-9e74-499ca0b38c4e.png)

3. Run taskschd.msc to open the Scheduler Task
4. Create a Task and use the service account you just created
5. Give the permission "Log on as Batch Job" to service account https://danblee.com/log-on-as-batch-job-rights-for-task-scheduler/
6. Run the scheduled task to test the result
7. Enjoy :)

<p align="center">
<img width="600" height="400" src="https://user-images.githubusercontent.com/5891788/191264530-bb4f2700-d91b-4e94-8bb8-ea57238e90ca.png">
<img src="https://user-images.githubusercontent.com/5891788/191264565-a5fe4a3c-b14d-4e5a-b6c0-efe741d4591d.png">
<img src="https://user-images.githubusercontent.com/5891788/191264503-cb3155a9-f2b3-4fed-b6de-eaf35b47a545.png">
</p>

## Acknowledgement

- Vincent Le Toux - https://twitter.com/mysmartlogon
- Romain Tiennot - https://github.com/aikiox
- Lilian Arago - https://github.com/NahisWayard

## License

MIT License
