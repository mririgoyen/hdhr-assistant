<?php
error_reporting(-1);
ini_set('display_errors', 'On');
if ($_SERVER['SERVER_ADDR'] == '::1')
	$_SERVER['SERVER_ADDR'] = '127.0.0.1';

// Instantiate class
require_once('Library.php');
$hdhr = new HDHRAssistant();

// Output M3U
$hdhr->generateM3U();