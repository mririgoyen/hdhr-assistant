<?php

/*
|--------------------------------------------------------------------------
| HDHR Assistant Config
|--------------------------------------------------------------------------
|
| Not all environments are the same. Here you can change several options
| which may be unique to your environment.
|
*/

return [

    // The IP address of the HDHomeRun on the local network
    'hdhr' => '192.168.1.104',

    // The path relative to the root these scripts are running from
    'path' => '/hdhr-assistant/',

    // The name of the xmltv.xml file
    'xmltv' => 'xmltv.xml',

    // The value in hours to shift the EPG time
    'epgshift' => 0,

    // Whether or not to show DRM protected channels
    'showdrm' => false,

    // Whether or not to use FFMPEG to provide service and provider strings:
    // *** WARNING: DO NOT CHANGE IF FFMPEG IS NOT INSTALLED!!! ***
    'use_ffmpeg' => false,

];