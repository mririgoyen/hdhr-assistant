<?php
// Instantiate class
require_once('Library.php');
$hdhr = new HDHRAssistant();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Channel Logo Inventory</title>
    <style>
    table {
        margin: 0 auto;
        text-align: center;
        width: 50%;
    }
    table thead {
        background-color: #a1a1a1;
    }
    table td {
        padding: 5px;
    }
    table tr:nth-child(even) {
        background-color: #e8e8e8;
    }
    img {
        max-width:50px;
        max-height:50px;
    }
    </style>
</head>
<body>
    <table>
        <thead>
            <tr>
                <th>Channel Number</th>
                <th>Channel Name</th>
                <th>Channel Logo</th>
            </tr>
        </thead>
        <tbody>

        <?php
        // If we have an array of channels, continue on
        if(is_array($hdhr->channels))
        {
            // Loop through and output channels
            foreach($hdhr->channels as $c)
            {
                // Start the table row
                echo '<tr>';

                // Output the channel number and name
                echo '<td>'.$c->GuideNumber.'</td>';
                echo '<td>'.$c->GuideName.'</td>';

                // Look for the image in the logos directory
                if(file_exists('logos/'.$c->GuideName.'.png'))
                {
                    echo '<td><img src="logos/'.$c->GuideName.'.png" alt="'.$c->GuideName.'"></td>';
                } else {
                    echo '<td><a href="https://www.google.com/#q='.$c->GuideName.'+lyngsat" target="_blank">[NONE - Click to Search]</a></td>';
                }

                // Close the table row
                echo '</tr>';
            }
        } else {
            echo '<tr><td colspan="3">No Channels Found</td></tr>';
        }
        ?>

        </tbody>
    </table>
</body>
</html>