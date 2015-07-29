HDHR Assistant
==============

The HDHR Assistant is a PHP library designed to run on your Synology NAS to
provide channel and an Electronic Programming Guide (EPG) for use in the 
IPTV Simple Client PVR add-on for Kodi.

Advantages
----------

 - Use Kodi's built-in Live TV interface, include Radio Stations
 - No need to launch any third-party applications
 - More control over how your channels display
 - Extensive EPG information

Disadvantages
-------------

 - You cannot record or pause live TV
 - Not as easy as just downloading and using the HDHomeRun VIEW application or Kodi add-on

Requirements
------------

 - Synology NAS with PHP web server enabled
 - HDHomeRun device on your local network
 - [Kodi 15+](http://kodi.tv/)
 - [IPTV Simple Client PVR add-on](http://kodi.wiki/view/Add-on:IPTV_Simple_Client)
 - Perl (To run the [Zap2XML](http://zap2xml.awardspace.info/) script, provided in this repository)

How to Use
----------

 1. Download this repository and place it in the root of your Synology web share in a directory called `hdhr-assistant`.
    - You can name the directory something else or even put it out of the root, just make sure you change the `config.php` file to reflect exactly where you put the files.

 2. Browse into `config` directory and edit the `config.php` file.

    - `hdhr` - The IP address of the HDHomeRun on your local network (e.g. `192.168.1.205`)
    - `path` - The path where you put these files. The default path is `/hdhr-assistant/`
    - `xmltv` - The name of the `xmltv.xml` file you generate with the Zap2XML PERL script.
    - `epgshift` - The value in hours to offset your EPG data. You most likely will not need to change this.
    - `showdrm` - Whether or not to include DRM protected channels in the listing. Copy-protected channels cannot be playing in Kodi, so they are hidden by default.

 3. **Optional:** There are two other configuration files:
    - `radio-sample.xml` - Defines channels which are radio stations.
    - `channels-sample.xml` - Allows you to override channel names that come from the EPG.

   Both of these files contain instructions and examples at the top of the file. Be sure to rename the files without the `-sample` for them to take affect!

How to Get EPG Data
-------------------
 1. Go to [http://tvschedule.zap2it.com/tvlistings/](http://tvschedule.zap2it.com/tvlistings/) and create an account.
    - Make sure you set your ZIP code and select your lineup.

 2. On Zap2It's site, set your preferences to *"Show six hour grid"*.

 3. On your Synology NAS, install Perl via the *Package Center*.

 4. Create a new scheduled task by going into the Synology *Control Panel*, then clicking on *Task Scheduler*.

 5. Click *Create* > *User-defined script*.

 6. Name your task **EPG Pull** and run as **root**.

 7. Under *Run command*, enter:

    `/volume1/web/hdhr-assistant/epg/zap2xml.pl -u YOUREMAIL -p YOURPASSWORD -F -o /volume1/web/hdhr-assistant/epg/xmltv.xml`

    - It is important to note that your paths might be different if you have more than one volume or if you copied this repository to a different location.

    - You the email address and password you signed up with on Zap2It's website.

 8. Click OK.

 9. Select the new task and click **Run** to test it. In about 30 seconds to a minute, you should have an xmltv.xml file in your epg directory.

How to Configure IPTV Simple Client
-----------------------------------

 1. Launch Kodi and go to your add-ons.

 2. Under PVR clients, find *PVR IPTV Simple Client* and select it.

 3. Select *Configure*.

 4. On the *General* tab:

    - **Location:** Remote Path (Internet address)
    - **M3U Play List URL:** `http://YOURNASIP/hdhr-assistant/Channels.php`
    - **Cache m3u at local storage:** Off

 5. On the *EPG Settings* tab:

    - **Location:** Remote Path (Internet address)
    - **M3U Play List URL:** `http://YOURNASIP/hdhr-assistant/epg/xmltv.xml`
    - **Cache XMLTV at local storage:** Off

 6. On the *Channels Logos* tab:

    - **Location:** Remote Path (Internet address)
    - **M3U Play List URL:** `http://YOURNASIP/hdhr-assistant/logos/`

 7. Select **OK**.

Channel Logos
-------------

There is a `logos` folder in the base of these files. Unfortunately, there is no automated task to retrieve channel logos. However, I have created a page to allow you to inventory which logos you have and which you need. You can access this by going to:

`http://YOURNASIP/hdhr-assistant/LogoInventory.php`

You must name the image file exactly as the channel name comes from your HDHomeRun, so this page is excellent for showing you want to name your file. **All images must be in PNG format!**

If you are missing a logo, there will be a link to a Google Search that may or may not help begin your search for that logo.

Simply place all the channel logos in this directory and they will show up on the inventory page and within Kodi!
