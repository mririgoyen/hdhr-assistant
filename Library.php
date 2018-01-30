<?php
/**
 * HDHRAssistant
 *
 * The HDHomeRun Channel Assistant is written to run on a
 * Synology NAS via the PHP web interface. It will query a
 * HDHomeRun on the local network and retrieve the tunable
 * channels and EPG data from Zap2It.
 * 
 * @author  Michael Irigoyen (goyney@gmail.com)
 */
 
 class HDHRAssistant {
    /**
     * Create all the storage arrays
     */
    protected $config    = array();
    public $overrides = array();
    public $channels     = array();
    public $epgmap       = array();

    /**
     * Verify a connection to the HDHomeRun
     * @return void
     */
    public function __construct()
    {
        // Load the configuration files
        $this->config                = @include('config/config.php');
        $this->overrides['radio']    = @include('config/radio.php');
        $this->overrides['channels'] = @include('config/channels.php');
        $this->overrides['exclude']  = @include('config/exclude.php');
        $this->overrides['remap']  = @include('config/remap_channels.php');

        // Check the HDHR connection and get the lineup URL from the device
        if(filter_var($this->config['hdhr'], FILTER_VALIDATE_IP)) {
            // Get HDHR discovery information
            $discovery = file_get_contents('http://'.$this->config['hdhr'].'/discover.json');
            if($discovery !== false) {
                // Parse the discovery information and get the lineup URL
                $discovery = json_decode($discovery, true);
                if(is_array($discovery) && array_key_exists('LineupURL', $discovery)) {
                    // Add the lineup URL to the config array
                    $this->config['lineup'] = $discovery['LineupURL'];
                } else {
                    // Couldn't get the lineup URL from the HDHomeRun
                    die('Unable to retrieve the lineup listing from the HDHomeRun.');
                }
            } else {
                // Couldn't communicate with the HDHomeRun
                die('Unable to communicate with the HDHomeRun at the provided IP address.');
            }
        } else {
            // Couldn't validate the IP address in the config file
            die('A valid IP address for the HDHomeRun was not set in the configuration file.');
        }

        // Get the channel listing from the HDHomeRun
        $this->parseHDHomeRunLineup();

        // Get the channel listing from the XMLTV file
        $this->parseXMLTVChannels();
    }

    /**
     * Reads the HDHomeRun lineup JSON file and puts it in memory
     * @return void
     */
    private function parseHDHomeRunLineup() {
        // Retrieve the lineup JSON file and parse it
        $channels = file_get_contents($this->config['lineup']);
        if($channels !== false) {
            // Set the channels to the global variable
            $this->channels = json_decode($channels);
        } else {
            // Throw an exception to prevent any other code from running
            die('Unable to find the `lineup.json` file. Please check the path.');
        }

		// Do we have any channel swaps to perform?
		if (is_array($this->overrides['remap']))
		{
			// Assign guide numbers as key for channel array:
			$channels = array();
			foreach ($this->channels as $c) {
				$channels[$c->GuideNumber] = $c;
			}

			// Swap the channels as requested in the configuration file:
			foreach ($this->overrides['remap'] as $c1 => $c2) {
				if (isset($channels[$c1]) && isset($channels[$c2])) {
					$channels[$c1]->GuideNumber = $c2;
					$channels[$c2]->GuideNumber = $c1;
					$tmp = $channels[$c1];
					$channels[$c1] = $channels[$c2];
					$channels[$c2] = $tmp;
				}
			}
			ksort($channels);
			$this->channels = $channels;
		}
    }

    /**
     * Reads the XMLTV file from Zap2It and makes an EPG mapping
     * @return void
     */
    private function parseXMLTVChannels() {
        $xml = new DOMDocument();
        if($xml->load('http://'.$_SERVER['SERVER_ADDR'].$this->config['path'].'/epg/'.$this->config['xmltv'])) {
            $channels = $xml->getElementsByTagName('channel');
            foreach($channels as $channel) {
                // Get the Zap2It channel ID
                $cid = $channel->getAttribute('id');

                // Get the channel number
                $dn = $channel->getElementsByTagName('display-name');

                // Add to the EPG mapping array
                $this->epgmap[$dn->item(2)->nodeValue] = $cid;
                $this->epgmap[$dn->item(1)->nodeValue] = $cid;
            }
        } else {
            // Couldn't find the xmltv.xml file in the epg directory
            die('Unable to find the `'.$this->config['xmltv'].'` file in /'.$this->config['path'].'/epg/');
        }
    }

    /**
     * Generates an M3U playlist based on the channel listing
     * @return void
     */
    public function generateM3U() {
        // Check to make sure we have channels and an EPG mapping
        if(is_array($this->channels) && is_array($this->epgmap)) {
            // Start the M3U playlist
            header('Content-Type: audio/mpegurl');
            header('Content-Disposition: attachment; filename="channels.m3u"'); 
            echo "#EXTM3U tvg-shift=".$this->config['epgshift']."\n";

            // Loop through and output channels
            foreach($this->channels as $c) {
				// Get station name from mess returned by HDHomerun:
				if (preg_match('#(.+?)([\d]{3,4})#i', $c->GuideName, $matches))
					$c->GuideName = empty($matches[1]) ? $c->GuideName : trim($matches[1]);
				
                // Check to see if this channel is excluded
                if(is_array($this->overrides['exclude']) && in_array($c->GuideNumber.' '.$c->GuideName, $this->overrides['exclude'])) {
                    // Excluded, skip to the next one
                    continue;
                }
                if (!isset($c->DRM))
					$c->DRM = 0;

                // Only show protected channels if configured to
                if(($this->config['showdrm'] === false && $c->DRM != 1) || $this->config['showdrm'] === true) {
                    // Check to see if this channel is a radio station
                    if(is_array($this->overrides['radio']) && array_key_exists($c->GuideNumber, $this->overrides['radio'])) {
                        // Output the radio station
                        echo '#EXTINF:-1 tvg-name="'.$c->GuideNumber.' '.$c->GuideName.'" tvg-logo="'.$c->GuideName.'" radio="true", '.$this->overrides['radio'][$c->GuideNumber]."\n";
                        echo $c->URL."\n";
                    } else {
                        // Set the channel name
                        $chname = $c->GuideName;

                        // Check to see if there is a channel name override
                        if(is_array($this->overrides['channels']) && array_key_exists($c->GuideNumber.' '.$c->GuideName, $this->overrides['channels'])) {
                            $chname = $this->overrides['channels'][$c->GuideNumber.' '.$c->GuideName];
                        }

                        // Add service and provider to stream if configured to do so:
						if($this->config['use_ffmpeg'] !== false) {
                        	$c->URL = 'pipe:///usr/bin/ffmpeg -loglevel fatal -i '.$c->URL.' -vcodec copy -acodec copy -metadata service_provider='.$c->GuideName.' -metadata service_name='.$c->GuideName.' -f mpegts -tune zerolatency pipe:1';
                        }

                        // Output the channel
                        echo '#EXTINF:-1 '.(array_key_exists($c->GuideName, $this->epgmap) ? 'tvg-id="'.$this->epgmap[$c->GuideName].'" ' : (array_key_exists($c->GuideNumber, $this->epgmap) ? 'tvg-id="'.$this->epgmap[$c->GuideNumber].'" ' : '')).'tvg-chno="'.$c->GuideNumber.'" tvg-name="'.$c->GuideName.'" tvg-logo="'.$c->GuideName.'", '.$c->GuideNumber.' '.$chname."\n";
                        echo $c->URL."\n";
                    }
                }
            }
        }
    }
}